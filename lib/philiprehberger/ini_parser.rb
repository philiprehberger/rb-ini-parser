# frozen_string_literal: true

require_relative 'ini_parser/version'
require_relative 'ini_parser/parser'
require_relative 'ini_parser/serializer'

module Philiprehberger
  module IniParser
    class Error < StandardError; end
    class ParseError < Error; end

    # Parse an INI string into a Hash.
    #
    # Top-level keys become global entries. Sections become nested Hashes.
    #
    # @param string [String] INI content
    # @param coerce_types [Boolean] coerce booleans, integers, and floats
    # @return [Hash] parsed configuration
    # @raise [ParseError] if the input contains invalid lines
    def self.parse(string, coerce_types: true)
      Parser.new.parse(string, coerce_types: coerce_types)
    end

    # Parse an INI file into a Hash.
    #
    # @param path [String] path to an INI file
    # @param coerce_types [Boolean] coerce booleans, integers, and floats
    # @return [Hash] parsed configuration
    # @raise [ParseError] if the file contains invalid lines
    # @raise [Errno::ENOENT] if the file does not exist
    def self.load(path, coerce_types: true)
      parse(File.read(path, encoding: 'utf-8'), coerce_types: coerce_types)
    end

    # Serialize a Hash to an INI string.
    #
    # @param hash [Hash] configuration data
    # @return [String] INI formatted string
    def self.dump(hash)
      Serializer.new.serialize(hash)
    end

    # Write a Hash to an INI file.
    #
    # @param hash [Hash] configuration data
    # @param path [String] output file path
    # @return [void]
    def self.save(hash, path)
      File.write(path, dump(hash), encoding: 'utf-8')
    end

    # Deep merge two INI configurations.
    #
    # Section-aware: when both hashes contain the same section key, the
    # section contents are merged rather than replaced.
    #
    # @param base [Hash] base configuration
    # @param override [Hash] overriding configuration
    # @return [Hash] merged result
    def self.merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          old_val.merge(new_val)
        else
          new_val
        end
      end
    end
  end
end
