# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "protocol/htty"

$stdout.binmode

Protocol::HTTY::Stream.new($stdout).write_bootstrap
