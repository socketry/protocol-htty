# frozen_string_literal: true

# HTTY server – HTTP/2 over a PTY, using the protocol-htty and protocol-http2 gems.
#
# Runs one HTTY session then exits so the shell can return to its prompt.
#
# Protocol flow:
#   1. Set raw mode so binary H2C bytes are not mangled by the line discipline.
#   2. Write the HTTY bootstrap DCS sequence to stdout (via Protocol::HTTY::Stream).
#   3. Wait for the HTTP/2 connection preface, then serve requests.
#   4. Send GOAWAY, close the framer, restore cooked mode, exit.
#
# Environment:
#   FAIL=y  Raise an error during request handling (tests the error path).

require "io/console"
require "protocol/htty"
require "protocol/http2"
require "protocol/http2/server"
require "protocol/http2/stream"

$stdout.binmode
$stdin.binmode

# Restore cooked mode on any exit, including unhandled exceptions.
# kill -9 bypasses this, but the shell restores its own saved termios when it
# reaps the child, so cooked mode is recovered either way.
at_exit {$stdin.cooked! rescue nil}

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
		method = headers[":method"] || "GET"
		path = headers[":path"] || "/"
		body = "Hello from HTTY! #{method} #{path}\n"
		
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

# 2. Open the HTTY stream, which writes the bootstrap DCS sequence to stdout.
stream = Protocol::HTTY::Stream.open($stdin, $stdout, bootstrap: :write)

# 3. Wait for the HTTP/2 connection preface, then serve requests.
#    The framer reads from the HTTY stream, which delegates to $stdin.
framer = Protocol::HTTP2::Framer.new(stream)
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

# 4. Send GOAWAY and close the framer (Protocol::HTTY::Stream#close does not
#    close the underlying stdin/stdout, so the terminal remains open).
server.close rescue nil
