# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "base64"
require "protocol/http2/framer"

module Protocol
	module HTTY
		# Encode and decode HTTY chunks on top of byte-oriented IO objects.
		class Framer
			ESC = "\e"
			DCS = "#{ESC}P"
			ST = "#{ESC}\\"
			PREFIX = "HTTY;1;"
			
			# Create a framer around the given input and output streams.
			# @parameter input [Interface(:read)] The stream to read framed packets from.
			# @parameter output [Interface(:write, :flush) | Nil] The stream to write framed packets to.
			def initialize(input, output = input)
				@input = input
				@output = output
			end
			
			attr :input
			attr :output
			
			# Write a single HTTY chunk to the output stream.
			# @parameter payload [String | Array(Integer)] The opaque bytes to encode.
			# @returns [void]
			def write_chunk(payload)
				encoded = Base64.strict_encode64(payload.to_s.b)
				@output.write("#{DCS}#{PREFIX}#{encoded}#{ST}")
			end
			
			# Read the next HTTY chunk from the input stream.
			# Non-HTTY terminal output is ignored until a valid chunk prefix is found.
			# @returns [String | Nil] The decoded payload, or `nil` on end of stream.
			# @raises [ProtocolError] If the chunk prefix or chunk structure is invalid.
			# @raises [ArgumentError] If the packet payload is not valid base64.
			# @raises [EOFError] If the chunk terminator is missing.
			def read_chunk
				while payload = read_payload
					if payload.start_with?("HTTY;") && !payload.start_with?(PREFIX)
						raise ProtocolError, "Unsupported HTTY chunk version: #{payload.inspect}"
					end
					
					next unless payload.start_with?(PREFIX)
					encoded = payload.delete_prefix(PREFIX)
					return Base64.strict_decode64(encoded)
				end
				
				return nil
			end
			
			# Flush the output stream if it supports flushing.
			# @returns [void]
			def flush
				@output.flush if @output.respond_to?(:flush)
			end
			
			# Close the wrapped input and output streams.
			# If input and output are the same object, it is only closed once.
			# @returns [void]
			def close
				@output.close if @output.respond_to?(:close)
				@input.close if !@input.equal?(@output) && @input.respond_to?(:close)
			end
			
			# Check whether the output stream has been closed.
			# @returns [bool] True if the output stream reports that it is closed.
			def closed?
				@output.respond_to?(:closed?) && @output.closed?
			end
			
			private
			
			def read_payload
				while prefix = @input.read(1)
					next unless prefix == ESC
					
					marker = @input.read(1)
					return nil unless marker
					next unless marker == "P"
					
					return consume_packet
				end
				
				return nil
			end
			
			def consume_packet
				buffer = +""
				
				while chunk = @input.read(1)
					if chunk == ESC
						terminator = @input.read(1)
						return buffer if terminator == "\\"
						
						buffer << chunk
						buffer << terminator if terminator
					else
						buffer << chunk
					end
				end
				
				raise EOFError, "Incomplete HTTY chunk!"
			end
		end
	end
end
