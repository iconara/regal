# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'regal/version'


Gem::Specification.new do |s|
  s.name          = 'regal'
  s.version       = Regal::VERSION.dup
  s.authors       = ['Theo Hultberg']
  s.email         = ['theo@iconara.net']
  s.homepage      = 'http://github.com/iconara/regal'
  s.summary       = %q{}
  s.description   = %q{}
  s.license       = 'BSD-3-Clause'

  s.files         = Dir['lib/**/*.rb', 'README.md', '.yardopts']
  s.test_files    = Dir['spec/**/*.rb']
  s.require_paths = %w(lib)

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.3'

  s.add_runtime_dependency 'rack', '>= 1.5'
end
