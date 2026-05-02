# philiprehberger-ini_parser

[![Tests](https://github.com/philiprehberger/rb-ini-parser/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-ini-parser/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-ini_parser.svg)](https://rubygems.org/gems/philiprehberger-ini_parser)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-ini-parser)](https://github.com/philiprehberger/rb-ini-parser/commits/main)

INI file parser and writer with section support and type coercion

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-ini_parser"
```

Or install directly:

```bash
gem install philiprehberger-ini_parser
```

## Usage

```ruby
require "philiprehberger/ini_parser"

config = Philiprehberger::IniParser.parse(<<~INI)
  name = MyApp

  [database]
  host = localhost
  port = 5432
  ssl = true
INI

config["name"]             # => "MyApp"
config["database"]["port"] # => 5432
config["database"]["ssl"]  # => true
```

### Loading from a File

```ruby
config = Philiprehberger::IniParser.load("config.ini")
```

### Serializing to INI

```ruby
hash = {
  "name" => "MyApp",
  "database" => { "host" => "localhost", "port" => 5432 }
}

ini_string = Philiprehberger::IniParser.dump(hash)
Philiprehberger::IniParser.save(hash, "output.ini")
```

### Inline Comments

```ruby
config = Philiprehberger::IniParser.parse(<<~INI)
  host = localhost ; the server host
  port = 8080 # default port
INI

config["host"] # => "localhost"
config["port"] # => 8080
```

### Multiline Values

```ruby
config = Philiprehberger::IniParser.parse("description = this is a\\\n  long value", coerce_types: false)
config["description"] # => "this is a long value"
```

### Escape Sequences

```ruby
config = Philiprehberger::IniParser.parse('msg = hello\nworld', coerce_types: false)
config["msg"] # => "hello\nworld"
```

### Variable Interpolation

Expand `${VAR}` references in values after parsing. Variables resolve first from parsed INI values (using `section.key` paths), then fall back to environment variables. Unresolved variables remain as-is.

```ruby
config = Philiprehberger::IniParser.parse(<<~INI, interpolate: true)
  [app]
  name = MyApp

  [logging]
  prefix = ${app.name}-log
INI

config["logging"]["prefix"] # => "MyApp-log"
```

### Environment Interpolation

Expand `${VAR}` and `${VAR:-default}` references from the process environment. Unset or empty variables fall back to the default (with surrounding whitespace trimmed) or an empty string when no default is given. Section headers and keys are never interpolated — values only. Use `$$` to emit a literal `$`.

```ruby
ENV["DB_HOST"] = "localhost"

config = Philiprehberger::IniParser.parse(<<~INI, interpolate_env: true)
  [database]
  host = ${DB_HOST}
  port = ${DB_PORT:-5432}
INI

config["database"]["host"] # => "localhost"
config["database"]["port"] # => "5432"
```

### Include Directives

Process `@include path/to/other.ini` lines to load and merge referenced files. Circular includes raise an error.

```ruby
# main.ini:
# @include database.ini
# name = MyApp

config = Philiprehberger::IniParser.parse(File.read("main.ini"), includes: true)
```

### Detailed Validation

Return an array of error hashes with line numbers instead of a simple boolean:

```ruby
errors = Philiprehberger::IniParser.validate("key = value\nnot valid ini\n[section]")
# => [{line: 2, message: "invalid line: not valid ini"}]
```

### Environment Export

Convert a parsed INI hash to flat `KEY=VALUE` format suitable for environment variables. Section keys become `SECTION_KEY=value` (uppercased with underscore separator).

```ruby
config = Philiprehberger::IniParser.parse(<<~INI)
  [database]
  host = localhost
  port = 5432
INI

env = Philiprehberger::IniParser.to_env(config)
# => "DATABASE_HOST=localhost\nDATABASE_PORT=5432"
```

### Disabling Type Coercion

```ruby
config = Philiprehberger::IniParser.parse(ini_string, coerce_types: false)
config["database"]["port"] # => "5432" (remains a string)
```

### Merging Configurations

```ruby
base = Philiprehberger::IniParser.load("defaults.ini")
local = Philiprehberger::IniParser.load("local.ini")

merged = Philiprehberger::IniParser.merge(base, local)
```

### Comparing Configurations

```ruby
a = Philiprehberger::IniParser.load("old.ini")
b = Philiprehberger::IniParser.load("new.ini")

diff = Philiprehberger::IniParser.diff(a, b)
diff[:added]   # => {"section" => {"new_key" => "value"}}
diff[:removed] # => {"section" => {"old_key" => "value"}}
diff[:changed] # => {"section" => {"key" => {from: "old", to: "new"}}}
```

### Dot-Path Access

Retrieve or set nested values using dot-separated paths:

```ruby
config = Philiprehberger::IniParser.load("config.ini")

Philiprehberger::IniParser.get(config, "database.host")                   # => "localhost"
Philiprehberger::IniParser.get(config, "database.missing", default: 3306) # => 3306

Philiprehberger::IniParser.set(config, "database.port", 5433)
```

### Validation

```ruby
Philiprehberger::IniParser.valid?("[section]\nkey = value") # => true
Philiprehberger::IniParser.valid?("not valid ini")          # => false
```

### Flatten / Unflatten

```ruby
config = Philiprehberger::IniParser.load("config.ini")

flat = Philiprehberger::IniParser.flatten(config)
# => {"name" => "MyApp", "database.host" => "localhost", "database.port" => 5432}

nested = Philiprehberger::IniParser.unflatten(flat)
# => {"name" => "MyApp", "database" => {"host" => "localhost", "port" => 5432}}
```

### Deleting by Path

```ruby
Philiprehberger::IniParser.delete(config, "database.host")
# => "localhost" (removed from config)
```

### Key Inspection

```ruby
config = Philiprehberger::IniParser.parse(<<~INI)
  name = MyApp

  [database]
  host = localhost
  port = 5432
INI

Philiprehberger::IniParser.keys(config)
# => ["name", "database.host", "database.port"]

Philiprehberger::IniParser.keys(config, section: "database")
# => ["host", "port"]

Philiprehberger::IniParser.has_key?(config, "database.host") # => true
Philiprehberger::IniParser.has_key?(config, "database.name") # => false
```

### Listing Sections

```ruby
sections = Philiprehberger::IniParser.sections("config.ini")
# => ["database", "logging", "cache"]
```

### Filter sections

```ruby
hash = Philiprehberger::IniParser.parse(ini_text)
Philiprehberger::IniParser.filter(hash, section: "database")
Philiprehberger::IniParser.filter(hash, section: ["database", "cache"])
```

### Section Existence Check

```ruby
hash = Philiprehberger::IniParser.parse(ini_text)
Philiprehberger::IniParser.has_section?(hash, "database")  # => true
Philiprehberger::IniParser.has_section?(hash, :missing)    # => false
```

## API

| Method | Description |
|--------|-------------|
| `IniParser.parse(string, coerce_types: true, interpolate: false, interpolate_env: false, includes: false)` | Parse an INI string into a Hash |
| `IniParser.load(path, coerce_types: true, interpolate: false, interpolate_env: false, includes: false)` | Parse an INI file into a Hash |
| `IniParser.dump(hash)` | Serialize a Hash to an INI string |
| `IniParser.save(hash, path)` | Write a Hash to an INI file |
| `IniParser.merge(base, override)` | Deep merge two INI configurations |
| `IniParser.diff(a, b)` | Compare two parsed hashes and return added, removed, and changed keys |
| `IniParser.valid?(string)` | Check if an INI string is syntactically valid |
| `IniParser.validate(string)` | Return array of `{ line:, message: }` hashes for each syntax error |
| `IniParser.to_env(hash)` | Convert parsed hash to flat `SECTION_KEY=value` environment format |
| `IniParser.get(hash, path, default: nil)` | Retrieve a value using a dot-separated path |
| `IniParser.set(hash, path, value)` | Set a value using a dot-separated path |
| `IniParser.flatten(hash)` | Convert nested sections to flat dot-separated keys |
| `IniParser.unflatten(hash)` | Convert dot-separated keys back to nested sections |
| `IniParser.keys(hash, section: nil)` | Return all keys; scoped to a section when given |
| `IniParser.has_key?(hash, path)` | Check if a dot-path key exists |
| `IniParser.delete(hash, path)` | Delete a value by dot-separated path, returns deleted value |
| `IniParser.sections(string_or_path)` | Extract section names without fully parsing values |
| `IniParser.filter(hash, section:)` | Return a copy of the hash containing only the named section(s) |
| `IniParser.has_section?(hash, name)` | Whether the hash has the given top-level section (Hash value) |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-ini-parser)

🐛 [Report issues](https://github.com/philiprehberger/rb-ini-parser/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-ini-parser/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
