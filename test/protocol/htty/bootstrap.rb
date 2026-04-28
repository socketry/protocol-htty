# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "stringio"
require "protocol/htty"

class OneByteInput
	def initialize(data)
		@data = data.b
		@offset = 0
	end
	
	def read(length = nil)
		return nil if @offset >= @data.bytesize
		
		length = [length || @data.bytesize, 1].min
		chunk = @data.byteslice(@offset, length)
		@offset += chunk.bytesize
		
		return chunk
	end
end

describe Protocol::HTTY::Stream do
	let(:input) {StringIO.new}
	let(:output) {StringIO.new}
	let(:io) {IO::Stream::Duplex(input, output)}
	let(:stream) {subject.new(io)}
	
	it "writes the HTTY raw bootstrap" do
		stream.write_bootstrap
		
		expect(output.string).to be == "\eP+Hraw\e\\"
	end
	
	it "reads the HTTY raw bootstrap" do
		input.string = "hello\eP+Hraw\e\\world"
		input.rewind
		
		mode = stream.read_bootstrap
		
		expect(mode).to be == "raw"
	end
	
	it "reads a bootstrap split across one-byte reads" do
		stream = subject.new(OneByteInput.new("hello\eP+Hraw\e\\"))
		
		expect(stream.read_bootstrap).to be == "raw"
	end
	
	it "preserves bytes after the HTTY bootstrap" do
		input.string = "\eP+Hraw\e\\world"
		input.rewind
		
		stream.read_bootstrap
		
		expect(io.read(5)).to be == "world"
	end
	
	it "raises on unsupported bootstrap modes" do
		input.string = "\eP+Hframed\e\\"
		input.rewind
		
		expect do
			stream.read_bootstrap
		end.to raise_exception(Protocol::HTTY::ProtocolError)
	end
	
	it "raises on incomplete bootstraps" do
		input.string = "\eP+Hraw"
		input.rewind
		
		expect do
			stream.read_bootstrap
		end.to raise_exception(EOFError)
	end
	
	it "ignores unrelated DCS payloads before the bootstrap" do
		input.string = "\ePfoo\e\\\eP+Hraw\e\\"
		input.rewind
		
		expect(stream.read_bootstrap).to be == "raw"
	end
	
	it "ignores implementation-specific reset markers before the bootstrap" do
		input.string = "\eP+reset:token\e\\\eP+Hraw\e\\"
		input.rewind
		
		expect(stream.read_bootstrap).to be == "raw"
	end
end
