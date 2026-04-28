# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

$stdout.binmode

$stdout.write("ignored output")
$stdout.write("\eP+reset:test-token\e\\")
$stdout.write("\eP+Hraw\e\\")
$stdout.write("RAW")
$stdout.flush
