# philiprehberger-ini_parser

[![Tests](https://github.com/philiprehberger/rb-ini-parser/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-ini-parser/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-ini_parser.svg)](https://rubygems.org/gems/philiprehberger-ini_parser)
[![License](https://img.shields.io/github/license/philiprehberger/rb-ini-parser)](LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ec6cb9)](https://github.com/sponsors/philiprehberger)

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

## API

| Method | Description |
|--------|-------------|
| `IniParser.parse(string, coerce_types: true)` | Parse an INI string into a Hash |
| `IniParser.load(path, coerce_types: true)` | Parse an INI file into a Hash |
| `IniParser.dump(hash)` | Serialize a Hash to an INI string |
| `IniParser.save(hash, path)` | Write a Hash to an INI file |
| `IniParser.merge(base, override)` | Deep merge two INI configurations |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

[MIT](LICENSE)
