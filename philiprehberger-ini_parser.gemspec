# frozen_string_literal: true

require_relative 'lib/philiprehberger/ini_parser/version'

Gem::Specification.new do |spec|
  spec.name = 'philiprehberger-ini_parser'
  spec.version = Philiprehberger::IniParser::VERSION
  spec.authors = ['Philip Rehberger']
  spec.email = ['me@philiprehberger.com']
  spec.summary = 'INI file parser and writer with section support and type coercion'
  spec.description = 'Parse and generate INI configuration files with sections, inline comments, ' \
                       'multiline values, escape sequences, quoted values, and automatic type coercion ' \
                       'for booleans and numbers.'
  spec.homepage = 'https://philiprehberger.com/open-source-packages/ruby/philiprehberger-ini_parser'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/philiprehberger/rb-ini-parser'
  spec.metadata['changelog_uri'] = 'https://github.com/philiprehberger/rb-ini-parser/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/philiprehberger/rb-ini-parser/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']
end
