# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "protocol/htty/version"

describe Protocol::HTTY do
	it "has a version number" do
		expect(Protocol::HTTY::VERSION).to be =~ /\d+\.\d+\.\d+/
	end
end
