# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "stringio"
require "protocol/http2/framer"
require "protocol/htty"

describe Protocol::HTTY::Stream do
	let(:writer) {StringIO.new}
	let(:stream) {subject.open(StringIO.new, writer)}
	
	it "writes raw bytes after bootstrap" do
		stream.write_bootstrap
		stream.write(Protocol::HTTP2::CONNECTION_PREFACE)
		stream.flush
		
		expect(writer.string).to be == "\eP+Hraw\e\\#{Protocol::HTTP2::CONNECTION_PREFACE}"
	end
	
	it "consumes the bootstrap before reading raw bytes" do
		writer.write("\eP+Hraw\e\\#{Protocol::HTTP2::CONNECTION_PREFACE}")
		writer.rewind
		
		reader = subject.open(writer, StringIO.new, bootstrap: :read)
		
		expect(reader.read(Protocol::HTTP2::CONNECTION_PREFACE.bytesize)).to be == Protocol::HTTP2::CONNECTION_PREFACE
		expect(reader.read).to be == ""
	end
	
	it "writes the bootstrap when opened in write mode" do
		writer = StringIO.new
		stream = subject.open(StringIO.new, writer, bootstrap: :write)
		
		expect(writer.string).to be == "\eP+Hraw\e\\"
		stream.close
	end
	
	it "returns all bytes when length is omitted" do
		writer.write("hello")
		writer.rewind
		
		reader = subject.open(writer, StringIO.new)
		
		expect(reader.read).to be == "hello"
		expect(reader.read).to be == ""
	end
	
	it "exposes the underlying output stream" do
		expect(stream.io).to be(:equal?, writer)
	end
	
	it "flushes through the underlying stream" do
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
	
	it "does not close the underlying output stream" do
		stream.close
		
		expect(writer).not.to be(:closed?)
	end
	
	it "close_write closes writes but preserves readability" do
		stream.close_write
		
		expect(stream).to be(:closed?)
		expect(stream).to be(:readable?)
		expect(writer).not.to be(:closed?)
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
end
