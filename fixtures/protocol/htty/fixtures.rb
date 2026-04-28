# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Protocol
	module HTTY
		module Fixtures
			ROOT = File.expand_path(__dir__)
			
			def self.executable_path(name)
				File.join(ROOT, "executables", "#{name}.rb")
			end
		end
	end
end
