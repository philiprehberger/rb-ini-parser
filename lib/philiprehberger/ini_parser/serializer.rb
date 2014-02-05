# frozen_string_literal: true

module Philiprehberger
  module IniParser
    # Converts a nested Hash back into an INI-formatted string.
    #
    # Top-level scalar keys are written as global key=value pairs.
    # Top-level Hash values are written as [section] groups.
    class Serializer
      # Serialize a Hash to an INI string.
      #
      # @param hash [Hash] configuration data
      # @return [String] INI formatted output
      def serialize(hash)
        globals, sections = partition(hash)
        lines = serialize_globals(globals)
        serialize_sections(sections, lines)
        lines << '' unless lines.empty?
        lines.join("\n")
      end

      private

      # Partition a hash into scalar globals and section hashes.
      #
      # @param hash [Hash]
      # @return [Array(Hash, Hash)]
      def partition(hash)
        globals = {}
        sections = {}

        hash.each do |key, value|
          if value.is_a?(Hash)
            sections[key.to_s] = value
          else
            globals[key.to_s] = value
          end
        end

        [globals, sections]
      end

      # Serialize global key-value pairs into lines.
      #
      # @param globals [Hash]
      # @return [Array<String>]
      def serialize_globals(globals)
        globals.map { |key, value| "#{key} = #{format_value(value)}" }
      end

      # Append section blocks to the lines array.
      #
      # @param sections [Hash]
      # @param lines [Array<String>]
      # @return [void]
      def serialize_sections(sections, lines)
        sections.each do |name, pairs|
          lines << '' unless lines.empty?
          lines << "[#{name}]"
          pairs.each { |key, value| lines << "#{key} = #{format_value(value)}" }
        end
      end

      # Format a single value for INI output.
      #
      # @param value [Object] the value to format
      # @return [String] formatted value
      def format_value(value)
        case value
        when true  then 'true'
        when false then 'false'
        when String then value
        else value.to_s
        end
      end
    end
  end
end
