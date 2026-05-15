# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Protocol
	module HTTY
		# Transport an opaque byte stream after the HTTY bootstrap handshake.
		class Stream
			ESC = "\e"
			DCS = "#{ESC}P"
			ST = "#{ESC}\\"
			BOOTSTRAP_PREFIX = "+H"
			RAW_MODE = "raw"
			
			def self.open(input, output, bootstrap: nil, mode: RAW_MODE)
				stream = self.new(input, output)
				
				# Disable buffering:
				input.sync = true
				output.sync = true
				
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
				@output = output
				@local_closed = false
			end
			
			# Required by {Protocol::HTTP::Peer} but not applicable to HTTY, which does not have a concept of remote addresses.
			def remote_address
				return nil
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
			# The HTTP/2 framer always requests exact byte counts (header size, then payload length), so we delegate directly to the underlying input.
			def read(length = nil)
				@input.read(length)
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
			
			def read_some(length)
				@input.read(length)
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
				buffer = String.new.b
				
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
