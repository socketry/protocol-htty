# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/console"
require "protocol/http2"
require "protocol/http2/server"
require "protocol/http2/stream"
require "protocol/htty"

$stdin.binmode
$stdout.binmode

at_exit {$stdin.cooked! rescue nil}

class PrefaceStream
	def initialize(input, output)
		@input = input
		@output = output
		@buffer = +"".b
	end
	
	def wait_for_preface
		until index = @buffer.index(Protocol::HTTP2::CONNECTION_PREFACE)
			@buffer << @input.readpartial(4096).b
		end
		
		@buffer = @buffer.byteslice(index, @buffer.bytesize) || +"".b
	end
	
	def read(length)
		while @buffer.bytesize < length
			@buffer << @input.readpartial(4096).b
		end
		
		data = @buffer.byteslice(0, length)
		@buffer = @buffer.byteslice(length, @buffer.bytesize) || +"".b
		
		return data
	end
	
	def write(data)
		@output.write(data)
	end
	
	def flush
		@output.flush
	end
	
	def close
		# The HTTP/2 framer must not close the PTY-backed standard streams.
	end
	
	def closed?
		false
	end
end

class RequestStream < Protocol::HTTP2::Stream
	def process_headers(frame)
		headers = super
		respond if frame.end_stream?
		return headers
	end
	
	def process_data(frame)
		data = super
		respond if frame.end_stream?
		return data
	end
	
	private
	
	def respond
		return if @responded
		
		@responded = true
		
		send_headers([[":status", "200"], ["content-type", "text/plain"]])
		send_data("OK\n", Protocol::HTTP2::END_STREAM)
		
		connection.session_complete!
	end
end

class Server < Protocol::HTTP2::Server
	def accept_stream(stream_id)
		RequestStream.create(self, stream_id)
	end
	
	def session_complete!
		@session_complete = true
	end
	
	def session_complete?
		@session_complete
	end
end

$stdin.raw! if $stdin.isatty
Protocol::HTTY::Stream.new($stdout).write_bootstrap

stream = PrefaceStream.new($stdin, $stdout)
stream.wait_for_preface

server = Server.new(Protocol::HTTP2::Framer.new(stream))
server.read_connection_preface

until server.session_complete?
	server.read_frame
end

server.send_goaway
server.close
