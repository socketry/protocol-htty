# frozen_string_literal: true
# HTTY client – starts a shell in a PTY, launches server.rb once per session,
# detects the HTTY bootstrap sequence, then makes an HTTP/2 GET request.
#
# Protocol flow (repeats for each HTTY session):
#   1. Start a shell in a PTY.
#   2. Write "ruby server.rb" to the shell for each session.
#   3. Scan PTY output for the HTTY bootstrap DCS sequence.
#   4. Exchange H2C connection prefaces and make a test GET request.
#   5. Send GOAWAY once the response is received.
#   6. Shell returns to its prompt; loop back to step 2.
#
# Environment:
#   HTTY_FAIL_ON=n  Pass FAIL=y to the server on session n, causing it to crash.
#   HTTY_SHELL=fish Use a different shell (default: bash).

require "pty"
require "timeout"
require "protocol/http2"
require "protocol/http2/client"
require "protocol/http2/stream"

SERVER       = File.join(__dir__, "server.rb")
BOOTSTRAP_RE = /\x1bP\+Hraw\x1b\\/n
FAIL_ON      = ENV["HTTY_FAIL_ON"]&.to_i

SHELL_CMD = case ENV.fetch("HTTY_SHELL", "bash")
            when "fish" then "fish --no-config"
            when "bash" then "bash --norc --noprofile"
            else ENV["HTTY_SHELL"]
            end

# ── Start shell ───────────────────────────────────────────────────────────────
# Step 1: spawn the shell in a PTY so the server sees a real TTY as stdin.
r, w, pid = PTY.spawn(SHELL_CMD)
r.binmode
w.binmode

# ── PTY stream ───────────────────────────────────────────────────────────────
# Wraps the PTY master as a single stream for Protocol::HTTP2::Framer.
# A single instance persists across sessions so that bytes the framer read
# ahead of a session boundary are not lost between sessions.
class PTYStream
  def initialize(r, w)
    @r   = r
    @w   = w
    @buf = "".b
  end

  # Scan buffered and incoming PTY bytes for the HTTY bootstrap DCS sequence.
  # Any bytes received after the sequence are retained in @buf for the framer.
  def wait_for_bootstrap
    loop do
      if (m = BOOTSTRAP_RE.match(@buf))
        @buf = m.post_match.b
        return
      end
      # $stderr.puts "[dbg] buf=#{@buf.bytesize}b, blocking on readpartial..."
      chunk = @r.readpartial(4096).b
      # $stderr.puts "[dbg] got #{chunk.bytesize}b: #{chunk[0, 60].inspect}"
      @buf = (@buf + chunk).force_encoding(Encoding::BINARY)
    rescue EOFError, Errno::EIO
      raise EOFError, "PTY closed"
    end
  end

  def read(n)
    while @buf.bytesize < n
      @buf << @r.readpartial(4096).b
    end
    data = @buf.byteslice(0, n)
    @buf = @buf.byteslice(n, @buf.bytesize) || "".b
    data
  rescue EOFError, Errno::EIO
    raise EOFError, "PTY closed"
  end

  def reset!
    @buf.clear

    token = "__HTTY_RESET_#{Process.pid}_#{object_id}_#{rand(1 << 32).to_s(16)}__"
    marker = "\x1bP+reset:#{token}\x1b\\"

    # This simulates what a user would do after a noisy crash: interrupt, clear
    # the current input line, and press Enter until the shell is usable again.
    # The marker is only for this automated client; it proves the shell reached
    # a fresh command boundary before the next HTTY session is queued.
    write("\x03\x15\r")
    write("printf '\\033P+reset:%s\\033\\\\' '#{token}'\r")
    flush

    Timeout.timeout(5) do
      loop do
        if (index = @buf.index(marker))
          @buf = @buf.byteslice(index + marker.bytesize, @buf.bytesize) || "".b
          return
        end

        @buf << @r.readpartial(4096).b
      end
    end
  rescue Timeout::Error
    raise Timeout::Error, "timed out waiting for shell reset marker"
  rescue EOFError, Errno::EIO
    raise EOFError, "PTY closed"
  end

  def write(data) = @w.write(data)
  def flush       = @w.flush
  def close       = (@r.close rescue nil; @w.close rescue nil)
  def closed?     = @r.closed?
end

# ── Response stream ──────────────────────────────────────────────────────────
class ResponseStream < Protocol::HTTP2::Stream
  attr_reader :response_headers, :body

  def initialize(*)
    super
    @response_headers = []
    @body             = "".b
  end

  def process_headers(frame)
    @response_headers = super
  end

  def process_data(frame)
    data = super
    @body << data.b if data
    data
  end
end

class HTTYClient < Protocol::HTTP2::Client
  def create_stream(id = next_stream_id) = ResponseStream.create(self, id)
end

# ── Main loop ────────────────────────────────────────────────────────────────
pty     = PTYStream.new(r, w)
session = 0

# Helper: write the server command to the shell, injecting FAIL=y when this
# is the session that should crash.
send_server_cmd = lambda do |n|
  cmd = (FAIL_ON == n) ? "FAIL=y ruby #{SERVER}" : "ruby #{SERVER}"
  w.write("#{cmd}\n")
  w.flush
end

# Step 2: kick off the first session before entering the loop.
send_server_cmd.call(1)

10.times do
  session += 1

  # Step 3: scan for HTTY bootstrap sequence.
  pty.wait_for_bootstrap
  $stderr.puts "[htty] bootstrap detected – session #{session}#{" (FAIL=y)" if FAIL_ON == session}"

  # Step 4: run the H2C session.
  framer = Protocol::HTTP2::Framer.new(pty)
  client = HTTYClient.new(framer)
  client.send_connection_preface

  stream = client.create_stream
  stream.send_headers(
    [[":method", "GET"], [":path", "/session/#{session}"],
     [":scheme", "http"], [":authority", "htty.local"]],
    Protocol::HTTP2::END_STREAM
  )

  loop do
    client.read_frame
    break if stream.closed?
  rescue EOFError, Errno::EIO, Protocol::HTTP2::GoawayError
    break
  rescue => e
    $stderr.puts "[htty] session #{session} error: #{e.class}: #{e.message}"
    break
  end

  session_ok = stream.response_headers.to_h.key?(":status")

  if session_ok
    headers = stream.response_headers.to_h
    puts "session #{session} – status: #{headers[":status"]}, body: #{stream.body.chomp}"

    # Step 5: send GOAWAY and tear down the framer.  PTYStream is not closed
    # so its internal buffer survives into the next bootstrap scan.
    client.send_goaway rescue nil
    $stderr.puts "[htty] session #{session} complete"
  else
    # Server crashed before responding.  Do NOT send GOAWAY: the connection is
    # broken and binary frame bytes would land in the shell's stdin as garbage.
    $stderr.puts "[htty] session #{session} failed – shell will restore terminal"
  end

  # Step 6: resynchronize with the shell before queuing the next session.
  $stderr.puts "queueing next session #{session + 1}"

  pty.reset!

  send_server_cmd.call(session + 1) if session < 10
end

# Close the PTY master to deliver EIO/SIGHUP to the shell and its children.
pty.close
Process.wait(pid) rescue nil
