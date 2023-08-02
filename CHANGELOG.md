# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-04-14

### Added
- `parse(string, interpolate: true)` to expand `${VAR}` references from parsed INI values or ENV
- `parse(string, includes: true)` to process `@include path/to/other.ini` directives with circular detection
- `validate(string)` to return an array of `{ line:, message: }` hashes for each syntax error
- `to_env(hash)` to convert parsed INI hash to flat `SECTION_KEY=value` environment format

## [0.4.0] - 2026-04-09

### Added
- `flatten(hash)` to convert nested sections to flat dot-separated keys
- `unflatten(hash)` to convert dot-separated keys back to nested sections
- `delete(hash, path)` to remove a value by dot-separated path

## [0.3.0] - 2026-04-09

### Added
- `valid?(string)` method to check INI syntax without raising exceptions
- `get(hash, path, default: nil)` for dot-path access to nested config values
- `set(hash, path, value)` for dot-path mutation of nested config values

## [0.2.1] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.2.0] - 2026-03-28

### Added

- Inline comment support for `;` and `#` delimiters after values
- Multiline values with backslash continuation
- Escape sequence handling (`\n`, `\t`, `\\`, `\;`, `\#`) in parse and dump
- `IniParser.diff(a, b)` to compare two parsed configurations
- `IniParser.sections(string_or_path)` to extract section names without full parse

## [0.1.1] - 2026-03-26

### Added

- Add GitHub funding configuration

## [0.1.0] - 2026-03-26

### Added
- Initial release
- Parse INI strings and files with section support
- Type coercion for booleans, integers, and floats
- Comment handling (semicolon and hash)
- Quoted string values (single and double quotes)
- Serialize Hash back to INI format
- Deep merge for section-aware configuration merging
