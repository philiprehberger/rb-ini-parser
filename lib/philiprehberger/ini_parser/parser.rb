# frozen_string_literal: true

module Philiprehberger
  module IniParser
    # Parses INI-formatted strings into nested Hashes.
    #
    # Supports sections, global keys, comments (; and #), blank lines,
    # quoted string values, and automatic type coercion for booleans,
    # integers, and floats.
    class Parser
      SECTION_RE = /\A\[([^\]]+)\]\z/
      COMMENT_RE = /\A\s*[;#]/
      KV_RE = /\A([^=]+)=(.*)?\z/

      # Parse an INI string into a Hash.
      #
      # @param string [String] INI content
      # @param coerce_types [Boolean] whether to coerce values to native types
      # @return [Hash] parsed configuration
      # @raise [ParseError] if a line cannot be parsed
      def parse(string, coerce_types: true)
        result = {}
        current_section = nil

        string.each_line do |raw_line|
          line = raw_line.strip
          next if skip?(line)

          current_section = process_line(line, raw_line, result, current_section, coerce_types)
        end

        result
      end

      private

      # Determine whether a line should be skipped.
      #
      # @param line [String] stripped line
      # @return [Boolean]
      def skip?(line)
        line.empty? || COMMENT_RE.match?(line)
      end

      # Process a single non-blank, non-comment line.
      #
      # @param line [String] stripped line
      # @param raw_line [String] original line for error messages
      # @param result [Hash] accumulating result
      # @param current_section [String, nil] active section name
      # @param coerce_types [Boolean] whether to coerce values
      # @return [String, nil] updated current section
      def process_line(line, raw_line, result, current_section, coerce_types)
        if (match = SECTION_RE.match(line))
          handle_section(match, result)
        elsif (match = KV_RE.match(line))
          handle_kv(match, result, current_section, coerce_types)
          current_section
        else
          raise ParseError, "invalid line: #{raw_line.chomp}"
        end
      end

      # Handle a section header line.
      #
      # @param match [MatchData] regex match
      # @param result [Hash] accumulating result
      # @return [String] section name
      def handle_section(match, result)
        section = match[1].strip
        result[section] ||= {}
        section
      end

      # Handle a key=value line.
      #
      # @param match [MatchData] regex match
      # @param result [Hash] accumulating result
      # @param current_section [String, nil] active section name
      # @param coerce_types [Boolean] whether to coerce values
      # @return [void]
      def handle_kv(match, result, current_section, coerce_types)
        key = match[1].strip
        value = parse_value(match[2]&.strip || '', coerce_types: coerce_types)
        target = current_section ? result[current_section] : result
        target[key] = value
      end

      # Parse a single value string, optionally coercing types.
      #
      # @param raw [String] raw value text
      # @param coerce_types [Boolean] whether to coerce
      # @return [String, Integer, Float, Boolean] parsed value
      def parse_value(raw, coerce_types:)
        return unquote(raw) if quoted?(raw)
        return raw unless coerce_types

        coerce(raw)
      end

      # Check whether the value is surrounded by matching quotes.
      #
      # @param value [String]
      # @return [Boolean]
      def quoted?(value)
        (value.start_with?('"') && value.end_with?('"')) ||
          (value.start_with?("'") && value.end_with?("'"))
      end

      # Remove surrounding quotes from a value.
      #
      # @param value [String]
      # @return [String]
      def unquote(value)
        value[1..-2]
      end

      # Coerce a string value to its native Ruby type.
      #
      # @param value [String]
      # @return [String, Integer, Float, Boolean]
      def coerce(value)
        case value
        when 'true'  then true
        when 'false' then false
        when /\A-?\d+\z/ then value.to_i
        when /\A-?\d+\.\d+\z/ then value.to_f
        else value
        end
      end
    end
  end
end
