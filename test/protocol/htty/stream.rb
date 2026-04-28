# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "stringio"
require "tempfile"
require "protocol/http2/framer"
require "protocol/htty"

describe Protocol::HTTY::Stream do
	let(:writer) {StringIO.new}
	let(:stream) {subject.new(StringIO.new, writer, packet_size: 8)}
	
	it "chunks opaque payload into HTTY chunks" do
		stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
		
		expect(writer.string.scan(/\ePHTTY;1;/).size).to be > 1
	end
	
	it "reads back opaque bytes from HTTY chunks" do
		stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
		writer.rewind
		
		reader = subject.new(writer, StringIO.new)
		
		expect(reader.read(Protocol::HTTP2::CONNECTION_PREFACE.bytesize)).to be == Protocol::HTTP2::CONNECTION_PREFACE
		reader.close
		expect(reader.read).to be_nil
	end
	
	it "returns all buffered bytes when length is omitted" do
		stream.write("hello")
		stream.close
		writer.rewind
		
		reader = subject.new(writer, StringIO.new)
		
		expect(reader.read).to be == "hello"
		expect(reader.read).to be_nil
	end
	
	it "exposes the underlying output stream" do
		expect(stream.io).to be(:is_a?, ::IO::Stream::Buffered)
	end
	
	it "flushes through the underlying framer" do
		stream.write("hello")
		
		expect do
			stream.flush
		end.not.to raise_exception
	end
	
	it "reports when the local side is closed" do
		expect(stream).not.to be(:closed?)
		
		stream.close
		
		expect(stream).to be(:closed?)
	end
	
	it "reports when the remote side is still readable" do
		expect(stream).to be(:readable?)
	end
	
	it "rejects writes after the local side is closed" do
		stream.close
		
		expect do
			stream.write("hello")
		end.to raise_exception(IOError)
	end
	
	it "wraps raw IO handles using IO::Stream" do
		Tempfile.create("protocol-htty") do |file|
			io_stream = subject.new(file, file).io
			
			expect(io_stream).to be(:is_a?, ::IO::Stream::Buffered)
			io_stream.close
		end
	end
end
