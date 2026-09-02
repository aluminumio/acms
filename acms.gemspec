require_relative "lib/acms/version"

Gem::Specification.new do |spec|
  spec.name = "acms"
  spec.version = Acms::VERSION
  spec.authors = [ "Aluminum" ]
  spec.summary = "Ruby client and CLI for Agent Content Management"
  spec.description = "Wallet-authenticated client for the agentcontentmanagement.com API, plus an importer that moves a Contentful space into a site."
  spec.homepage = "https://github.com/aluminumio/acms"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = [ "acms" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "keccak", "~> 1.3"
  spec.add_dependency "rbsecp256k1", "~> 6.0"
end
