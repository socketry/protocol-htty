# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/stream"

module Protocol
	module HTTY
		# Transport an opaque byte stream after the HTTY bootstrap handshake.
		class Stream
			ESC = "\e"
			DCS = "#{ESC}P"
			ST = "#{ESC}\\"
			BOOTSTRAP_PREFIX = "+H"
			RAW_MODE = "raw"
			
			HTTP2_FRAME_HEADER_SIZE = 9
			
			def self.open(input, output, bootstrap: nil, mode: RAW_MODE)
				stream = self.new(input, output)
				
				case bootstrap
				when :write
					stream.write_bootstrap(mode)
				when :read
					actual_mode = stream.read_bootstrap
					
					unless actual_mode == mode
						raise ProtocolError, "Expected HTTY bootstrap mode #{mode.inspect}, got #{actual_mode.inspect}"
					end
				end
				
				return stream
			end
			
			# Create a stream on top of raw byte-preserving endpoints.
			# @parameter input [IO] The readable endpoint.
			# @parameter output [IO] The writable endpoint.
			def initialize(input, output)
				@input = input
				@output = ::IO::Stream(output)
				@frame_remaining = nil
				@local_closed = false
			end
			
			attr :input
			attr :output
			
			# Return the underlying output stream.
			def io
				@output
			end
			
			def write_bootstrap(mode = RAW_MODE)
				@output.write("#{DCS}#{BOOTSTRAP_PREFIX}#{mode}#{ST}")
				@output.flush
			end
			
			def read_bootstrap
				while payload = read_payload
					next unless payload.start_with?(BOOTSTRAP_PREFIX)
					mode = payload.delete_prefix(BOOTSTRAP_PREFIX)
					
					unless mode == RAW_MODE
						raise ProtocolError, "Unsupported HTTY bootstrap mode: #{mode.inspect}"
					end
					
					return mode
				end
				
				return nil
			end
			
			# Read application bytes from the HTTY transport.
			def read(length = nil)
				if length == 0
					@frame_remaining = nil if @frame_remaining == 0
					return +"".b
				end
				
				requested_length = length
				length = [length, @frame_remaining].min if length && @frame_remaining && @frame_remaining > 0
				buffer = read_exact(length)
				
				if buffer && requested_length == HTTP2_FRAME_HEADER_SIZE && !@frame_remaining
					if buffer.bytesize == HTTP2_FRAME_HEADER_SIZE
						frame_length = self.class.frame_length(buffer)
						@frame_remaining = frame_length if frame_length > 0
					end
				elsif buffer && @frame_remaining
					@frame_remaining -= buffer.bytesize
					@frame_remaining = nil if @frame_remaining <= 0
				end
				
				return buffer
			end
			
			# Write application bytes after bootstrap.
			# @returns [self]
			# @raises [IOError] If the local side of the transport is closed.
			def write(data, flush: false)
				raise IOError, "HTTY stream is closed for writing!" if @local_closed
				
				@output.write(data.to_s.b)
				@output.flush if flush
				
				return self
			end
			
			# Flush any buffered output through the underlying stream.
			# @returns [void]
			def flush
				@output.flush
			end
			
			# Close the local write side of this stream abstraction.
			# HTTY does not define a close packet, and closing this object does not close the underlying terminal IO.
			# @returns [void]
			def close_write(error = nil)
				unless @local_closed
					@local_closed = true
					@output.flush
				end
			end
			
			alias close close_write
			
			# Check whether the local side of the transport is closed.
			# @returns [bool] True if local writes have been closed.
			def closed?
				@local_closed
			end
			
			# Check whether the remote side may still provide more data.
			# @returns [bool] True if the remote side has not sent or implied a close.
			def readable?
				!(@input.respond_to?(:closed?) && @input.closed?)
			end
			
			private
			
			def self.frame_length(buffer)
				length_high, length_low = buffer.unpack("Cn")
				return (length_high << 16) | length_low
			end
			
			def read_exact(length)
				return @input.read if length.nil?
				
				buffer = +"".b
				
				while buffer.bytesize < length
					chunk = read_some(length - buffer.bytesize)
					break unless chunk
					
					buffer << chunk.b
				end
				
				return nil if buffer.empty?
				return buffer
			end
			
			def read_some(length)
				if @input.respond_to?(:readpartial)
					@input.readpartial(length)
				else
					@input.read(length)
				end
			rescue EOFError, Errno::EIO
				return nil
			end
			
			def read_payload
				while prefix = read_some(1)
					next unless prefix == ESC
					
					marker = read_some(1)
					return nil unless marker
					next unless marker == "P"
					
					return consume_packet
				end
				
				return nil
			end
			
			def consume_packet
				buffer = +""
				
				while chunk = read_some(1)
					if chunk == ESC
						terminator = read_some(1)
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
