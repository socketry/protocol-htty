# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/stream"

module Protocol
	module HTTY
		# Transport an opaque byte stream over HTTY chunks.
		class Stream
			# Since base64 encoding adds 33% overhead, we can fit 3KB of binary data into a single HTTY chunk without exceeding the typical MTU of 4KB:
			PACKET_SIZE = 1024*3
			
			# Create a stream on top of HTTY framed input and output.
			# @parameter input [IO | IO::Stream] The source of framed HTTY chunks.
			# @parameter output [IO | IO::Stream | Nil] The sink for framed HTTY chunks.
			# @parameter packet_size [Integer] The maximum payload size for each chunk.
			def initialize(input, output = input, packet_size: PACKET_SIZE)
				@framer = Framer.new(::IO::Stream(input), ::IO::Stream(output))
				@packet_size = packet_size
				@buffer = +"".b
				@local_closed = false
				@remote_closed = false
			end
			
			attr :framer
			
			# Return the writable IO object used by the underlying framer.
			# @returns [IO | IO::Stream] The output side of the framed transport.
			def io
				@framer.output
			end
			
			# Read application bytes from the HTTY transport.
			# @parameter length [Integer | Nil] The exact number of bytes to read, or `nil` for all buffered bytes.
			# @returns [String | Nil] The requested bytes, an empty binary string for `0`, or `nil` if more data is required or the remote side is closed.
			def read(length = nil)
				return +"".b if length == 0
				
				fill(length)
				
				return nil if @buffer.empty? && @remote_closed
				return nil if @buffer.empty?
				return nil if length && @buffer.bytesize < length && !@remote_closed
				
				if length
					return @buffer.slice!(0, length)
				else
					return @buffer.slice!(0, @buffer.bytesize)
				end
			end
			
			# Write application bytes as one or more HTTY chunks.
			# @parameter data [String | Array(Integer)] The opaque bytes to send.
			# @returns [self]
			# @raises [IOError] If the local side of the transport is closed.
			def write(data)
				raise IOError, "HTTY stream is closed for writing!" if @local_closed
				
				data = data.to_s.b
				
				until data.empty?
					chunk = data.byteslice(0, @packet_size)
					@framer.write_chunk(chunk)
					data = data.byteslice(chunk.bytesize..)
				end
				
				@framer.flush
				
				return self
			end
			
			# Flush any buffered output through the underlying framer.
			# @returns [void]
			def flush
				@framer.flush
			end
			
			# Close the local side of the transport.
			# HTTY does not define a close packet; remote peers observe closure via the underlying transport.
			# @returns [void]
			def close
				unless @local_closed
					@local_closed = true
					@framer.flush
				end
			end
			
			# Check whether the local side of the transport is closed.
			# @returns [bool] True if local writes have been closed.
			def closed?
				@local_closed
			end
			
			# Check whether the remote side may still provide more data.
			# @returns [bool] True if the remote side has not sent or implied a close.
			def readable?
				!@remote_closed
			end
			
			private
			
			def fill(length)
				while needs_more_data?(length)
					chunk = @framer.read_chunk
					
					unless chunk
						@remote_closed = true
						break
					end
					@buffer << chunk
				end
			end
			
			def needs_more_data?(length)
				return false if @remote_closed
				return @buffer.empty? unless length
				
				@buffer.bytesize < length
			end
		end
	end
end
