# frozen_string_literal: true

require_relative 'lib/pd4ml/version'

Gem::Specification.new do |spec|
  spec.name = 'pd4ml'
  spec.version = Pd4ml::VERSION
  spec.authors = ['PD4ML']
  spec.email = ['support@pd4ml.com']
  spec.summary = 'PD4ML for Ruby: HTML and CSS to PDF, PDF/A, PDF/UA, ZUGFeRD, DOCX, RTF and images'
  spec.description = 'The full public PD4ML API in Ruby. PD4ML runs in a Java bridge process; the most recent ' \
                     'PD4ML build is downloaded on first use.'
  spec.homepage = 'https://github.com/zxfr/pd4ml-ruby'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.1'
  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'documentation_uri' => 'https://pd4ml.com/docs/',
    'rubygems_mfa_required' => 'true',
  }

  spec.files = Dir['lib/**/*.{rb,jar}', 'exe/*', 'docs/*.md', 'README.md']
  spec.bindir = 'exe'
  spec.executables = ['pd4ml']
  spec.require_paths = ['lib']
end
