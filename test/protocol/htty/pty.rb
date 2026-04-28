# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "open3"
require "pty"
require "rbconfig"
require "timeout"
require "protocol/http2"
require "protocol/http2/client"
require "protocol/http2/stream"
require "protocol/htty"
require "protocol/htty/fixtures"

class PTYStream
	def initialize(input, output)
		@input = input
		@output = output
		@buffer = +"".b
	end
	
	def read(length)
		while @buffer.bytesize < length
			@buffer << @input.readpartial(4096).b
		end
		
		data = @buffer.byteslice(0, length)
		@buffer = @buffer.byteslice(length, @buffer.bytesize) || +"".b
		
		return data
	rescue EOFError, Errno::EIO
		raise EOFError, "PTY closed"
	end
	
	def write(data)
		@output.write(data)
	end
	
	def flush
		@output.flush
	end
	
	def close
		@input.close rescue nil
		@output.close rescue nil
	end
	
	def closed?
		@input.closed?
	end
end

class ResponseStream < Protocol::HTTP2::Stream
	attr :response_headers
	attr :body
	
	def initialize(...)
		super
		@response_headers = []
		@body = +"".b
	end
	
	def process_headers(frame)
		@response_headers = super
	end
	
	def process_data(frame)
		data = super
		@body << data.b if data
		return data
	end
end

class Client < Protocol::HTTP2::Client
	def create_stream(id = next_stream_id)
		ResponseStream.create(self, id)
	end
end

describe "HTTY over a real PTY" do
	let(:root) {File.expand_path("../../..", __dir__)}
	let(:ruby_load_path) {File.join(root, "lib")}
	
	def spawn_fixture(name)
		environment = {"RUBYLIB" => ruby_load_path}
		
		PTY.spawn(environment, RbConfig.ruby, Protocol::HTTY::Fixtures.executable_path(name))
	end
	
	def with_fixture(name)
		input, output, pid = spawn_fixture(name)
		input.binmode
		output.binmode
		
		stream = PTYStream.new(input, output)
		
		yield stream
	ensure
		stream&.close
		Process.wait(pid) rescue nil
	end
	
	it "ignores terminal noise before the bootstrap" do
		Timeout.timeout(5) do
			with_fixture("bootstrap") do |stream|
				framer = Protocol::HTTY::Stream.new(stream)
				
				expect(framer.read_bootstrap).to be == "raw"
				expect(stream.read(3)).to be == "RAW"
			end
		end
	end
	
	it "delivers the HTTP/2 connection preface after raw takeover" do
		Timeout.timeout(5) do
			with_fixture("raw_preface") do |stream|
				framer = Protocol::HTTY::Stream.new(stream)
				
				expect(framer.read_bootstrap).to be == "raw"
				
				stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
				stream.flush
				
				expect(stream.read(10)).to be == "PREFACE_OK"
			end
		end
	end
	
	it "runs an HTTP/2 session until command-side GOAWAY" do
		Timeout.timeout(5) do
			with_fixture("http2_server") do |stream|
				Protocol::HTTY::Stream.new(stream).read_bootstrap
				
				framer = Protocol::HTTP2::Framer.new(stream)
				client = Client.new(framer)
				client.send_connection_preface
				
				request = client.create_stream
				request.send_headers(
					[[":method", "GET"], [":path", "/"], [":scheme", "http"], [":authority", "htty.local"]],
					Protocol::HTTP2::END_STREAM
				)
				
				goaway = false
				
				until goaway
					begin
						frame = client.read_frame
						goaway = frame.is_a?(Protocol::HTTP2::GoawayFrame)
					rescue Protocol::HTTP2::GoawayError
						goaway = true
					end
				end
				
				expect(request.response_headers.to_h[":status"]).to be == "200"
				expect(request.body).to be == "OK\n"
			end
		end
	end
	
	it "treats command exit after bootstrap without GOAWAY as an abort" do
		Timeout.timeout(5) do
			with_fixture("abort_after_bootstrap") do |stream|
				expect(Protocol::HTTY::Stream.new(stream).read_bootstrap).to be == "raw"
				
				framer = Protocol::HTTP2::Framer.new(stream)
				
				expect do
					framer.read_frame
				end.to raise_exception(EOFError)
			end
		end
	end
	
	it "recovers the surrounding shell after an aborted session" do
		client = File.join(root, "examples/pty/client.rb")
		
		output, error, status = Timeout.timeout(10) do
			Open3.capture3(
				{"HTTY_SHELL" => "bash", "HTTY_FAIL_ON" => "5"},
				RbConfig.ruby,
				client,
				chdir: root
			)
		end
		
		combined_output = "#{output}#{error}"
		
		expect(status).to be(:success?)
		expect(combined_output).to be(:include?, "[htty] session 5 failed")
		expect(combined_output).to be(:include?, "[htty] bootstrap detected \u2013 session 6")
		expect(combined_output).to be(:include?, "session 10 \u2013 status: 200")
	end
end
