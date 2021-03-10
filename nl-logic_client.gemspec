# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nl/logic_client/version'

Gem::Specification.new do |spec|
  spec.name          = "logic_system"
  spec.version       = NL::LogicClient::VERSION
  spec.authors       = ["Mike Bourgeous"]
  spec.email         = ["mike@mikebourgeous.com"]

  spec.summary       = %q{Ruby client for the Automation Controller logic backend.}
  spec.description   = %q{Ruby client for the Automation Controller logic backend.}
  spec.homepage      = "https://github.com/nitrogenlogic/nl-logic_client"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "Public release not allowed."
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end


  basedir = ENV['LOGIC_GEM_SOURCE'] || File.expand_path('..', __FILE__)
  spec.files         = `cd "#{basedir}"; git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 1.9.3'

  spec.add_runtime_dependency 'eventmachine'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.0.1"
end
