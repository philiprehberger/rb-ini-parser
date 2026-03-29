# frozen_string_literal: true

module Philiprehberger
  module IniParser
    # Parses INI-formatted strings into nested Hashes.
    #
    # Supports sections, global keys, comments (; and #), blank lines,
    # quoted string values, inline comments, multiline values with
    # backslash continuation, escape sequences, and automatic type
    # coercion for booleans, integers, and floats.
    class Parser
      SECTION_RE = /\A\[([^\]]+)\]\z/
      COMMENT_RE = /\A\s*[;#]/
      KV_RE = /\A([^=]+)=(.*)?\z/
      CONTINUATION_RE = /\\\s*\z/

      ESCAPE_MAP = {
        'n' => "\n",
        't' => "\t",
        '\\' => '\\',
        ';' => ';',
        '#' => '#'
      }.freeze

      # Parse an INI string into a Hash.
      #
      # @param string [String] INI content
      # @param coerce_types [Boolean] whether to coerce values to native types
      # @return [Hash] parsed configuration
      # @raise [ParseError] if a line cannot be parsed
      def parse(string, coerce_types: true)
        result = {}
        current_section = nil
        continuation_key = nil
        continuation_value = nil
        continuation_target = nil

        string.each_line do |raw_line|
          line = raw_line.strip

          if continuation_key
            continuation_value, continuation_key, continuation_target = handle_continuation(
              line, continuation_key, continuation_value, continuation_target, coerce_types
            )
            next
          end

          next if skip?(line)

          current_section, continuation_key, continuation_value, continuation_target = process_line(
            line, raw_line, result, current_section, coerce_types
          )
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
      # @return [Array] updated current section and continuation state
      def process_line(line, raw_line, result, current_section, coerce_types)
        if (match = SECTION_RE.match(line))
          [handle_section(match, result), nil, nil, nil]
        elsif (match = KV_RE.match(line))
          handle_kv_with_continuation(match, result, current_section, coerce_types)
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

      # Handle a key=value line, detecting backslash continuations.
      #
      # @param match [MatchData] regex match
      # @param result [Hash] accumulating result
      # @param current_section [String, nil] active section name
      # @param coerce_types [Boolean] whether to coerce values
      # @return [Array] current_section, continuation_key, continuation_value, continuation_target
      def handle_kv_with_continuation(match, result, current_section, coerce_types)
        key = match[1].strip
        raw_value = match[2]&.strip || ''
        target = current_section ? result[current_section] : result

        if CONTINUATION_RE.match?(raw_value)
          base = raw_value.sub(CONTINUATION_RE, '')
          [current_section, key, base, target]
        else
          value = parse_value(raw_value, coerce_types: coerce_types)
          target[key] = value
          [current_section, nil, nil, nil]
        end
      end

      # Handle a continuation line.
      #
      # @param line [String] stripped continuation line
      # @param key [String] the key being continued
      # @param accumulated [String] accumulated value so far
      # @param target [Hash] hash to store the final value
      # @param coerce_types [Boolean] whether to coerce values
      # @return [Array] updated continuation_value, continuation_key, continuation_target
      def handle_continuation(line, key, accumulated, target, coerce_types)
        if CONTINUATION_RE.match?(line)
          appended = line.sub(CONTINUATION_RE, '')
          ["#{accumulated} #{appended}", key, target]
        else
          final_raw = "#{accumulated} #{line}"
          value = parse_value(final_raw, coerce_types: coerce_types)
          target[key] = value
          [nil, nil, nil]
        end
      end

      # Parse a single value string, optionally coercing types.
      #
      # @param raw [String] raw value text
      # @param coerce_types [Boolean] whether to coerce
      # @return [String, Integer, Float, Boolean] parsed value
      def parse_value(raw, coerce_types:)
        return unescape(unquote(raw)) if quoted?(raw)

        stripped = strip_inline_comment(raw)
        unescaped = unescape(stripped)
        return unescaped unless coerce_types

        coerce(unescaped)
      end

      # Strip inline comments from a value.
      #
      # Inline comments start with an unescaped ; or # preceded by whitespace.
      # Escaped delimiters (\; and \#) are preserved.
      #
      # @param value [String]
      # @return [String]
      def strip_inline_comment(value)
        i = 0
        while i < value.length
          if value[i] == '\\'
            i += 2
            next
          end

          if [';', '#'].include?(value[i]) && i.positive? && value[i - 1] == ' '
            return value[0, i].rstrip
          end

          i += 1
        end
        value
      end

      # Unescape escape sequences in a value.
      #
      # @param value [String]
      # @return [String]
      def unescape(value)
        result = +''
        i = 0
        while i < value.length
          if value[i] == '\\' && i + 1 < value.length
            next_char = value[i + 1]
            if ESCAPE_MAP.key?(next_char)
              result << ESCAPE_MAP[next_char]
              i += 2
            else
              result << value[i]
              i += 1
            end
          else
            result << value[i]
            i += 1
          end
        end
        result
      end

      # Check whether the value is surrounded by matching quotes.
      #
      # @param value [String]
      # @return [Boolean]
      def quoted?(value)
        (value.start_with?('"') && value.end_with?('"') && value.length >= 2) ||
          (value.start_with?("'") && value.end_with?("'") && value.length >= 2)
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
