# frozen_string_literal: true

require_relative 'ini_parser/version'
require_relative 'ini_parser/parser'
require_relative 'ini_parser/serializer'

module Philiprehberger
  module IniParser
    class Error < StandardError; end
    class ParseError < Error; end

    SECTION_RE = /\A\s*\[([^\]]+)\]\s*\z/

    INTERPOLATION_RE = /\$\{([^}]+)\}/

    # Parse an INI string into a Hash.
    #
    # Top-level keys become global entries. Sections become nested Hashes.
    #
    # @param string [String] INI content
    # @param coerce_types [Boolean] coerce booleans, integers, and floats
    # @param interpolate [Boolean] expand ${VAR} references after parsing
    # @param includes [Boolean] process @include directives
    # @return [Hash] parsed configuration
    # @raise [ParseError] if the input contains invalid lines
    # @raise [Error] if circular includes are detected
    def self.parse(string, coerce_types: true, interpolate: false, includes: false)
      if includes
        string = process_includes(string, [])
      end

      result = Parser.new.parse(string, coerce_types: coerce_types)

      if interpolate
        interpolate_hash(result, result)
      end

      result
    end

    # Parse an INI file into a Hash.
    #
    # @param path [String] path to an INI file
    # @param coerce_types [Boolean] coerce booleans, integers, and floats
    # @param interpolate [Boolean] expand ${VAR} references after parsing
    # @param includes [Boolean] process @include directives
    # @return [Hash] parsed configuration
    # @raise [ParseError] if the file contains invalid lines
    # @raise [Errno::ENOENT] if the file does not exist
    # @raise [Error] if circular includes are detected
    def self.load(path, coerce_types: true, interpolate: false, includes: false)
      parse(File.read(path, encoding: 'utf-8'), coerce_types: coerce_types, interpolate: interpolate, includes: includes)
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

    # Validate an INI string and return detailed errors.
    #
    # Returns an array of hashes, each with :line and :message keys,
    # describing syntax errors found in the input. Returns an empty
    # array if the content is valid.
    #
    # @param string [String] INI content
    # @return [Array<Hash{Symbol => Object}>] validation errors
    def self.validate(string)
      errors = []
      line_number = 0
      in_continuation = false

      string.each_line do |raw_line|
        line_number += 1
        line = raw_line.strip

        if in_continuation
          in_continuation = line.end_with?('\\')
          next
        end

        next if line.empty?
        next if line.match?(/\A\s*[;#]/)

        if line.match?(/\A\[([^\]]+)\]\z/)
          next
        end

        if line.match?(/\A([^=]+)=(.*)?\z/)
          raw_value = (line.split('=', 2)[1] || '').strip
          in_continuation = raw_value.match?(/\\\s*\z/)
          next
        end

        errors << { line: line_number, message: "invalid line: #{raw_line.chomp}" }
      end

      errors
    end

    # Convert a parsed INI hash to flat KEY=VALUE environment format.
    #
    # Section keys become SECTION_KEY=value (uppercased with underscore
    # separator). Global keys are simply uppercased.
    #
    # @param hash [Hash] parsed configuration
    # @return [String] environment variable format
    def self.to_env(hash)
      lines = []

      hash.each do |key, value|
        if value.is_a?(Hash)
          value.each do |sub_key, sub_val|
            env_key = "#{key}_#{sub_key}".upcase
            lines << "#{env_key}=#{sub_val}"
          end
        else
          lines << "#{key.upcase}=#{value}"
        end
      end

      lines.join("\n")
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

    # Process @include directives in INI content.
    #
    # @param string [String] INI content
    # @param seen [Array<String>] already-included file paths for circular detection
    # @return [String] content with includes expanded
    # @raise [Error] if circular includes are detected
    # @api private
    def self.process_includes(string, seen)
      lines = []

      string.each_line do |raw_line|
        line = raw_line.strip
        if line.match?(/\A@include\s+/)
          path = line.sub(/\A@include\s+/, '').strip
          resolved = File.expand_path(path)

          if seen.include?(resolved)
            raise Error, "circular include detected: #{resolved}"
          end

          included_content = File.read(resolved, encoding: 'utf-8')
          lines << process_includes(included_content, seen + [resolved])
        else
          lines << raw_line
        end
      end

      lines.join
    end
    private_class_method :process_includes

    # Interpolate ${VAR} references in all string values of a hash.
    #
    # Resolves references first from the parsed INI values (section.key),
    # then falls back to ENV. Unresolved variables remain as-is.
    #
    # @param hash [Hash] the hash to interpolate (mutated in place)
    # @param root [Hash] the full parsed hash for lookups
    # @api private
    def self.interpolate_hash(hash, root)
      hash.each do |key, value|
        if value.is_a?(Hash)
          interpolate_hash(value, root)
        elsif value.is_a?(String)
          hash[key] = interpolate_value(value, root)
        end
      end
    end
    private_class_method :interpolate_hash

    # Interpolate ${VAR} references in a single string value.
    #
    # @param value [String] the string to interpolate
    # @param root [Hash] the full parsed hash for lookups
    # @return [String] interpolated value
    # @api private
    def self.interpolate_value(value, root)
      value.gsub(INTERPOLATION_RE) do |match|
        ref = ::Regexp.last_match(1)
        resolved = resolve_reference(ref, root)
        resolved.nil? ? match : resolved.to_s
      end
    end
    private_class_method :interpolate_value

    # Resolve a variable reference from parsed values or ENV.
    #
    # Supports dot-separated paths (section.key) for INI lookups.
    #
    # @param ref [String] variable reference (e.g. "section.key" or "VAR")
    # @param root [Hash] the full parsed hash
    # @return [Object, nil] resolved value or nil
    # @api private
    def self.resolve_reference(ref, root)
      parts = ref.split('.')
      current = root

      parts.each do |part|
        return ENV.fetch(ref, nil) unless current.is_a?(Hash) && current.key?(part)

        current = current[part]
      end

      current
    end
    private_class_method :resolve_reference
  end
end
