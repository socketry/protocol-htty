# frozen_string_literal: true

require_relative "lib/protocol/htty/version"

Gem::Specification.new do |spec|
	spec.name = "protocol-htty"
	spec.version = Protocol::HTTY::VERSION
	
	spec.summary = "A terminal-safe transport for carrying opaque HTTP/2 bytes over TTY side channels."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/protocol-htty"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/protocol-htty/",
		"source_code_uri" => "https://github.com/socketry/protocol-htty.git",
	}
	
	spec.files = Dir.glob(["{lib,test}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.3"
	
	spec.add_dependency "base64"
	spec.add_dependency "protocol-http2"
	spec.add_dependency "io-stream"
end
