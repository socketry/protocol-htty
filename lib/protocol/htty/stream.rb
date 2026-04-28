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
			
			def self.open(stream, bootstrap: nil, mode: RAW_MODE)
				stream = self.new(::IO::Stream(stream))
				
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
			
			# Create a stream on top of a raw byte-preserving transport.
			# @parameter stream [IO::Stream] The duplex byte stream used after bootstrap.
			def initialize(stream)
				@stream = stream
				@local_closed = false
			end
			
			attr :stream
			
			# Return the underlying duplex stream.
			def io
				@stream
			end
			
			def write_bootstrap(mode = RAW_MODE)
				@stream.write("#{DCS}#{BOOTSTRAP_PREFIX}#{mode}#{ST}")
				@stream.flush
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
				return +"".b if length == 0
				return @stream.read(length)
			end
			
			# Write application bytes after bootstrap.
			# @returns [self]
			# @raises [IOError] If the local side of the transport is closed.
			def write(data)
				raise IOError, "HTTY stream is closed for writing!" if @local_closed
				
				@stream.write(data.to_s.b)
				
				return self
			end
			
			# Flush any buffered output through the underlying stream.
			# @returns [void]
			def flush
				@stream.flush
			end
			
			# Close the local write side of this stream abstraction.
			# HTTY does not define a close packet, and closing this object does not close the underlying terminal IO.
			# @returns [void]
			def close_write(error = nil)
				unless @local_closed
					@local_closed = true
					@stream.flush
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
				!@stream.closed?
			end
			
			private
			
			def read_payload
				while prefix = @stream.read(1)
					next unless prefix == ESC
					
					marker = @stream.read(1)
					return nil unless marker
					next unless marker == "P"
					
					return consume_packet
				end
				
				return nil
			end
			
			def consume_packet
				buffer = +""
				
				while chunk = @stream.read(1)
					if chunk == ESC
						terminator = @stream.read(1)
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
