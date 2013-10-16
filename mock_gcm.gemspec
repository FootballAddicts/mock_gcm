# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mock_gcm/version'

Gem::Specification.new do |spec|
  spec.name          = "mock_gcm"
  spec.version       = MockGCM::VERSION
  spec.authors       = ["Anders Carling"]
  spec.email         = ["anders.carling@d05.se"]
  spec.description   = %q{Fake GCM server for your integration testing needs}
  spec.summary       = %q{Fake GCM server for your integration testing needs}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "httpclient"
end
