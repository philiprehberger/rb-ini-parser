# frozen_string_literal: true

require_relative 'ini_parser/version'
require_relative 'ini_parser/parser'
require_relative 'ini_parser/serializer'

module Philiprehberger
  module IniParser
    class Error < StandardError; end
    class ParseError < Error; end

    SECTION_RE = /\A\s*\[([^\]]+)\]\s*\z/

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

    # Compare two parsed INI hashes and return a diff.
    #
    # @param a [Hash] first configuration (from parse)
    # @param b [Hash] second configuration (from parse)
    # @return [Hash] diff with :added, :removed, and :changed keys
    def self.diff(a, b)
      result = { added: {}, removed: {}, changed: {} }

      all_keys = (a.keys + b.keys).uniq

      all_keys.each do |key|
        in_a = a.key?(key)
        in_b = b.key?(key)

        if in_a && in_b
          diff_key(key, a[key], b[key], result)
        elsif in_b
          add_to_result(result[:added], key, b[key])
        else
          add_to_result(result[:removed], key, a[key])
        end
      end

      result
    end

    # Check whether an INI string is syntactically valid.
    #
    # @param string [String] INI content
    # @return [Boolean] true if the content parses without errors
    def self.valid?(string)
      parse(string)
      true
    rescue ParseError
      false
    end

    # Retrieve a value from a parsed hash using a dot-separated path.
    #
    # @param hash [Hash] parsed configuration
    # @param path [String] dot-separated key path (e.g. "database.host")
    # @param default [Object] value to return if the path does not exist
    # @return [Object] the value at the path, or the default
    def self.get(hash, path, default: nil)
      keys = path.to_s.split('.')
      current = hash

      keys.each do |key|
        return default unless current.is_a?(Hash) && current.key?(key)

        current = current[key]
      end

      current
    end

    # Set a value in a parsed hash using a dot-separated path.
    #
    # Creates intermediate section hashes as needed.
    #
    # @param hash [Hash] parsed configuration (mutated in place)
    # @param path [String] dot-separated key path (e.g. "database.host")
    # @param value [Object] the value to set
    # @return [Object] the value that was set
    def self.set(hash, path, value)
      keys = path.to_s.split('.')
      last = keys.pop
      current = hash

      keys.each do |key|
        current[key] = {} unless current[key].is_a?(Hash)
        current = current[key]
      end

      current[last] = value
    end

    # Flatten a nested INI hash to dot-separated keys.
    #
    # @param hash [Hash] parsed configuration
    # @return [Hash{String => Object}] flat hash with dot-separated keys
    def self.flatten(hash)
      result = {}
      hash.each do |key, value|
        if value.is_a?(Hash)
          value.each { |sub_key, sub_val| result["#{key}.#{sub_key}"] = sub_val }
        else
          result[key.to_s] = value
        end
      end
      result
    end

    # Convert a flat dot-separated hash back to nested sections.
    #
    # @param hash [Hash{String => Object}] flat hash with dot-separated keys
    # @return [Hash] nested configuration hash
    def self.unflatten(hash)
      result = {}
      hash.each do |key, value|
        parts = key.to_s.split('.', 2)
        if parts.length == 2
          result[parts[0]] ||= {}
          result[parts[0]][parts[1]] = value
        else
          result[parts[0]] = value
        end
      end
      result
    end

    # Delete a value by dot-separated path.
    #
    # @param hash [Hash] parsed configuration (mutated in place)
    # @param path [String] dot-separated key path (e.g. "database.host")
    # @return [Object, nil] the deleted value, or nil if the path did not exist
    def self.delete(hash, path)
      keys = path.to_s.split('.')
      last = keys.pop
      current = hash

      keys.each do |key|
        return nil unless current.is_a?(Hash) && current.key?(key)

        current = current[key]
      end

      return nil unless current.is_a?(Hash)

      current.delete(last)
    end

    # Extract section names from INI content without fully parsing values.
    #
    # @param string_or_path [String] INI content string or file path
    # @return [Array<String>] section names
    def self.sections(string_or_path)
      content = File.exist?(string_or_path) ? File.read(string_or_path, encoding: 'utf-8') : string_or_path
      names = []

      content.each_line do |line|
        match = SECTION_RE.match(line.strip)
        names << match[1].strip if match
      end

      names
    end

    # @api private
    def self.diff_key(key, val_a, val_b, result)
      if val_a.is_a?(Hash) && val_b.is_a?(Hash)
        diff_section(key, val_a, val_b, result)
      elsif val_a.is_a?(Hash)
        result[:removed][key] = val_a
        add_to_result(result[:added], key, val_b)
      elsif val_b.is_a?(Hash)
        add_to_result(result[:removed], key, val_a)
        result[:added][key] = val_b
      elsif val_a != val_b
        result[:changed][key] ||= {}
        result[:changed][key] = { from: val_a, to: val_b }
      end
    end
    private_class_method :diff_key

    # @api private
    def self.diff_section(section, hash_a, hash_b, result)
      all_sub_keys = (hash_a.keys + hash_b.keys).uniq

      all_sub_keys.each do |sub_key|
        in_a = hash_a.key?(sub_key)
        in_b = hash_b.key?(sub_key)

        if in_a && in_b
          if hash_a[sub_key] != hash_b[sub_key]
            result[:changed][section] ||= {}
            result[:changed][section][sub_key] = { from: hash_a[sub_key], to: hash_b[sub_key] }
          end
        elsif in_b
          result[:added][section] ||= {}
          result[:added][section][sub_key] = hash_b[sub_key]
        else
          result[:removed][section] ||= {}
          result[:removed][section][sub_key] = hash_a[sub_key]
        end
      end
    end
    private_class_method :diff_section

    # @api private
    def self.add_to_result(hash, key, value)
      hash[key] = value
    end
    private_class_method :add_to_result
  end
end
