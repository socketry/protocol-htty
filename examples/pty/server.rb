# frozen_string_literal: true
# HTTY server – HTTP/2 over a PTY, using the protocol-http2 gem.
#
# Runs one HTTY session then exits so the shell can return to its prompt.
#
# Protocol flow:
#   1. Set raw mode so binary H2C bytes are not mangled by the line discipline.
#   2. Write the HTTY bootstrap DCS sequence to stdout.
#   3. Wait for the HTTP/2 connection preface, then serve requests.
#   4. Send GOAWAY, close the framer, restore cooked mode, exit.
#
# Environment:
#   FAIL=y  Raise an error during request handling (tests the error path).

require "io/console"
require "protocol/http2"
require "protocol/http2/server"
require "protocol/http2/stream"

HTTY_BOOTSTRAP = "\x1bP+Hraw\x1b\\"
PREFACE        = Protocol::HTTP2::CONNECTION_PREFACE

$stdout.binmode
$stdin.binmode

# Restore cooked mode on any exit, including unhandled exceptions.
# kill -9 bypasses this, but the shell restores its own saved termios when it
# reaps the child, so cooked mode is recovered either way.
at_exit { $stdin.cooked! rescue nil }

# ── IO wrapper ───────────────────────────────────────────────────────────────
class PrefaceStream
  def initialize(read_io, write_io)
    @r   = read_io
    @w   = write_io
    @buf = "".b
  end

  # Discard bytes until the HTTP/2 connection preface appears at the head of
  # the buffer.  Any bytes already buffered are checked before reading more.
  def wait_for_preface
    loop do
      if (i = @buf.index(PREFACE))
        @buf = @buf.byteslice(i, @buf.bytesize)
        return
      end
      @buf << @r.readpartial(4096).b
    rescue EOFError, Errno::EIO
      exit 0
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
    raise EOFError, "stdin closed"
  end

  def write(data) = @w.write(data)
  def flush       = @w.flush
  def close       = nil   # leave stdin/stdout open; framer must not close the TTY
  def closed?     = false
end

# ── Request stream ───────────────────────────────────────────────────────────
class RequestStream < Protocol::HTTP2::Stream
  def process_headers(frame)
    @req_headers = super
    respond if frame.end_stream?
    @req_headers
  end

  def process_data(frame)
    data = super
    respond if frame.end_stream?
    data
  end

  private

  def respond
    return if @responded
    @responded = true

    raise RuntimeError, "Simulated crash (FAIL=y)" if ENV["FAIL"]

    headers = @req_headers.to_h
    method  = headers[":method"] || "GET"
    path    = headers[":path"]   || "/"
    body    = "Hello from HTTY! #{method} #{path}\n"

    send_headers([[":status", "200"], ["content-type", "text/plain; charset=utf-8"]])
    send_data(body, Protocol::HTTP2::END_STREAM)

    connection.session_complete!
  end
end

class HTTYServer < Protocol::HTTP2::Server
  def accept_stream(stream_id) = RequestStream.create(self, stream_id)

  def session_complete! = @session_complete = true
  def session_complete? = @session_complete
end

# ── Single session ────────────────────────────────────────────────────────────

# 1. Set raw mode before announcing HTTY readiness.
$stdin.raw! if $stdin.isatty

# 2. Send bootstrap sequence.
$stdout.write(HTTY_BOOTSTRAP)
$stdout.flush

# 3. Wait for the HTTP/2 connection preface.
io = PrefaceStream.new($stdin, $stdout)
io.wait_for_preface

framer = Protocol::HTTP2::Framer.new(io)
server = HTTYServer.new(framer)
server.read_connection_preface

loop do
  server.read_frame
  break if server.session_complete?
rescue EOFError, Errno::EIO, Protocol::HTTP2::GoawayError
  break
rescue => e
  # Unexpected errors are fatal; at_exit restores cooked mode.
  $stderr.puts "#{e.class}: #{e.message}"
  raise
end

# 4. Send GOAWAY and close the framer (PrefaceStream#close is a no-op).
server.close rescue nil
