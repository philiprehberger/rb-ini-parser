# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
