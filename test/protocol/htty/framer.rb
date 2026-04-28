# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "stringio"
require "protocol/http2/framer"
require "protocol/htty"

describe Protocol::HTTY::Framer do
	let(:input) {StringIO.new}
	let(:output) {StringIO.new}
	let(:framer) {subject.new(input, output)}
	
	it "writes terminal-safe chunks" do
		framer.write_chunk(Protocol::HTTP2::CONNECTION_PREFACE)
		
		expect(output.string).to be == "\ePHTTY;1;UFJJICogSFRUUC8yLjANCg0KU00NCg0K\e\\"
	end
	
	it "reads terminal-safe chunks" do
		input.string = "hello\ePHTTY;1;UFJJICogSFRUUC8yLjANCg0KU00NCg0K\e\\world"
		input.rewind
		
		chunk = framer.read_chunk
		
		expect(chunk).to be == Protocol::HTTP2::CONNECTION_PREFACE
	end
	
	it "raises on malformed chunks" do
		input.string = "\ePHTTY;1\e\\"
		input.rewind
		
		expect do
			framer.read_chunk
		end.to raise_exception(Protocol::HTTY::ProtocolError)
	end
	
	it "raises on incomplete chunks" do
		input.string = "\ePHTTY;1;QUJD"
		input.rewind
		
		expect do
			framer.read_chunk
		end.to raise_exception(EOFError)
	end
	
	it "closes distinct input and output streams" do
		framer.close
		
		expect(input).to be(:closed?)
		expect(output).to be(:closed?)
		expect(framer).to be(:closed?)
	end
	
	it "handles escaped bytes inside an invalid chunk payload" do
		input.string = "\ePHTTY;1;QUJD\eXRA==\e\\"
		input.rewind
		
		expect do
			framer.read_chunk
		end.to raise_exception(ArgumentError)
	end
end
