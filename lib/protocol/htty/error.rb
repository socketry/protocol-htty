# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

# @namespace
module Protocol
	# @namespace
	module HTTY
		# The base class for HTTY transport errors.
		class Error < StandardError
		end
		
		# Raised when an HTTY control packet is malformed or unsupported.
		class ProtocolError < Error
		end
	end
end
