# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/console"
require "protocol/http2"
require "protocol/htty"

$stdin.binmode
$stdout.binmode

at_exit {$stdin.cooked! rescue nil}

$stdin.raw! if $stdin.isatty
Protocol::HTTY::Stream.new($stdin, $stdout).write_bootstrap

preface = $stdin.read(Protocol::HTTP2::CONNECTION_PREFACE.bytesize)

if preface == Protocol::HTTP2::CONNECTION_PREFACE
	$stdout.write("PREFACE_OK")
else
	$stdout.write("PREFACE_BAD")
end

$stdout.flush
