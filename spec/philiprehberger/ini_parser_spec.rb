# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Philiprehberger::IniParser do
  it 'has a version number' do
    expect(Philiprehberger::IniParser::VERSION).not_to be_nil
  end

  describe '.parse' do
    it 'parses global key-value pairs' do
      ini = "name = MyApp\nversion = 2"
      result = described_class.parse(ini)

      expect(result).to eq('name' => 'MyApp', 'version' => 2)
    end

    it 'parses sections into nested hashes' do
      ini = <<~INI
        [database]
        host = localhost
        port = 5432
      INI

      result = described_class.parse(ini)

      expect(result).to eq('database' => { 'host' => 'localhost', 'port' => 5432 })
    end

    it 'parses global keys and sections together' do
      ini = <<~INI
        name = MyApp

        [database]
        host = localhost
        port = 5432
        ssl = true

        [logging]
        level = info
        file = /var/log/app.log
      INI

      result = described_class.parse(ini)

      expect(result).to eq(
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432, 'ssl' => true },
        'logging' => { 'level' => 'info', 'file' => '/var/log/app.log' }
      )
    end

    it 'coerces boolean values' do
      ini = "enabled = true\ndisabled = false"
      result = described_class.parse(ini)

      expect(result['enabled']).to be true
      expect(result['disabled']).to be false
    end

    it 'coerces integer values' do
      ini = "port = 8080\nnegative = -42"
      result = described_class.parse(ini)

      expect(result['port']).to eq(8080)
      expect(result['negative']).to eq(-42)
    end

    it 'coerces float values' do
      ini = "rate = 3.14\nneg = -0.5"
      result = described_class.parse(ini)

      expect(result['rate']).to eq(3.14)
      expect(result['neg']).to eq(-0.5)
    end

    it 'skips type coercion when disabled' do
      ini = "port = 8080\nenabled = true"
      result = described_class.parse(ini, coerce_types: false)

      expect(result['port']).to eq('8080')
      expect(result['enabled']).to eq('true')
    end

    it 'ignores semicolon comments' do
      ini = "; this is a comment\nname = value"
      result = described_class.parse(ini)

      expect(result).to eq('name' => 'value')
    end

    it 'ignores hash comments' do
      ini = "# this is a comment\nname = value"
      result = described_class.parse(ini)

      expect(result).to eq('name' => 'value')
    end

    it 'ignores blank lines' do
      ini = "a = 1\n\n\nb = 2"
      result = described_class.parse(ini)

      expect(result).to eq('a' => 1, 'b' => 2)
    end

    it 'handles double-quoted string values without coercion' do
      ini = 'port = "8080"'
      result = described_class.parse(ini)

      expect(result['port']).to eq('8080')
    end

    it 'handles single-quoted string values without coercion' do
      ini = "enabled = 'true'"
      result = described_class.parse(ini)

      expect(result['enabled']).to eq('true')
    end

    it 'handles values with equals signs' do
      ini = 'formula = a=b+c'
      result = described_class.parse(ini)

      expect(result['formula']).to eq('a=b+c')
    end

    it 'handles empty values' do
      ini = 'empty ='
      result = described_class.parse(ini)

      expect(result['empty']).to eq('')
    end

    it 'raises ParseError for invalid lines' do
      ini = "name = valid\nthis is not valid ini"
      expect { described_class.parse(ini) }.to raise_error(Philiprehberger::IniParser::ParseError)
    end
  end

  describe 'inline comments' do
    it 'strips semicolon inline comments' do
      ini = 'host = localhost ; the server host'
      result = described_class.parse(ini)

      expect(result['host']).to eq('localhost')
    end

    it 'strips hash inline comments' do
      ini = 'port = 8080 # default port'
      result = described_class.parse(ini)

      expect(result['port']).to eq(8080)
    end

    it 'preserves escaped semicolons in values' do
      ini = 'formula = a\;b'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['formula']).to eq('a;b')
    end

    it 'preserves escaped hashes in values' do
      ini = 'color = \#ff0000'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['color']).to eq('#ff0000')
    end

    it 'strips inline comments in sections' do
      ini = <<~INI
        [database]
        host = localhost ; primary host
        port = 5432 # postgres default
      INI

      result = described_class.parse(ini)

      expect(result['database']['host']).to eq('localhost')
      expect(result['database']['port']).to eq(5432)
    end

    it 'does not strip comment chars without preceding space' do
      ini = 'url = http://example.com/path#anchor'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['url']).to eq('http://example.com/path#anchor')
    end

    it 'does not strip comments from quoted values' do
      ini = 'msg = "hello ; world"'
      result = described_class.parse(ini)

      expect(result['msg']).to eq('hello ; world')
    end
  end

  describe 'multiline values' do
    it 'joins backslash-continued lines' do
      ini = "key = line1\\\n  line2"
      result = described_class.parse(ini, coerce_types: false)

      expect(result['key']).to eq('line1 line2')
    end

    it 'joins multiple continuation lines' do
      ini = "key = part1\\\n  part2\\\n  part3"
      result = described_class.parse(ini, coerce_types: false)

      expect(result['key']).to eq('part1 part2 part3')
    end

    it 'trims leading whitespace on continuation lines' do
      ini = "key = hello\\\n    world"
      result = described_class.parse(ini, coerce_types: false)

      expect(result['key']).to eq('hello world')
    end

    it 'works within sections' do
      ini = <<~INI
        [section]
        description = this is a\\\n  long value
      INI

      result = described_class.parse(ini, coerce_types: false)

      expect(result['section']['description']).to eq('this is a long value')
    end
  end

  describe 'escape sequences' do
    it 'unescapes \\n to newline' do
      ini = 'msg = hello\\nworld'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['msg']).to eq("hello\nworld")
    end

    it 'unescapes \\t to tab' do
      ini = 'msg = col1\\tcol2'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['msg']).to eq("col1\tcol2")
    end

    it 'unescapes \\\\ to backslash' do
      ini = 'path = C:\\\\Users\\\\test'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['path']).to eq('C:\\Users\\test')
    end

    it 'unescapes \\; to literal semicolon' do
      ini = 'data = value\\;more'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['data']).to eq('value;more')
    end

    it 'unescapes \\# to literal hash' do
      ini = 'color = \\#red'
      result = described_class.parse(ini, coerce_types: false)

      expect(result['color']).to eq('#red')
    end

    it 'handles escape sequences in quoted values' do
      ini = 'msg = "hello\\nworld"'
      result = described_class.parse(ini)

      expect(result['msg']).to eq("hello\nworld")
    end
  end

  describe '.load' do
    it 'parses an INI file from disk' do
      file = Tempfile.new(['test', '.ini'])
      file.write("[server]\nhost = 127.0.0.1\nport = 3000\n")
      file.close

      result = described_class.load(file.path)

      expect(result).to eq('server' => { 'host' => '127.0.0.1', 'port' => 3000 })
    ensure
      file&.unlink
    end

    it 'raises Errno::ENOENT for missing files' do
      expect { described_class.load('/nonexistent/file.ini') }.to raise_error(Errno::ENOENT)
    end
  end

  describe '.dump' do
    it 'serializes global keys' do
      hash = { 'name' => 'MyApp', 'version' => 1 }
      result = described_class.dump(hash)

      expect(result).to eq("name = MyApp\nversion = 1\n")
    end

    it 'serializes sections' do
      hash = { 'database' => { 'host' => 'localhost', 'port' => 5432 } }
      result = described_class.dump(hash)

      expect(result).to eq("[database]\nhost = localhost\nport = 5432\n")
    end

    it 'serializes globals and sections together' do
      hash = {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'ssl' => true }
      }
      result = described_class.dump(hash)

      expect(result).to include('name = MyApp')
      expect(result).to include('[database]')
      expect(result).to include('host = localhost')
      expect(result).to include('ssl = true')
    end

    it 'serializes boolean values' do
      hash = { 'flags' => { 'enabled' => true, 'debug' => false } }
      result = described_class.dump(hash)

      expect(result).to include('enabled = true')
      expect(result).to include('debug = false')
    end

    it 'escapes newlines in string values' do
      hash = { 'msg' => "hello\nworld" }
      result = described_class.dump(hash)

      expect(result).to include('msg = hello\nworld')
    end

    it 'escapes tabs in string values' do
      hash = { 'msg' => "col1\tcol2" }
      result = described_class.dump(hash)

      expect(result).to include('msg = col1\tcol2')
    end

    it 'escapes backslashes in string values' do
      hash = { 'path' => 'C:\\Users' }
      result = described_class.dump(hash)

      expect(result).to include('path = C:\\\\Users')
    end

    it 'escapes semicolons in string values' do
      hash = { 'data' => 'a;b' }
      result = described_class.dump(hash)

      expect(result).to include('data = a\\;b')
    end

    it 'escapes hashes in string values' do
      hash = { 'color' => '#red' }
      result = described_class.dump(hash)

      expect(result).to include('color = \\#red')
    end
  end

  describe '.save' do
    it 'writes an INI file to disk' do
      file = Tempfile.new(['test', '.ini'])
      file.close

      hash = { 'server' => { 'host' => '0.0.0.0', 'port' => 8080 } }
      described_class.save(hash, file.path)

      content = File.read(file.path)

      expect(content).to include('[server]')
      expect(content).to include('host = 0.0.0.0')
      expect(content).to include('port = 8080')
    ensure
      file&.unlink
    end
  end

  describe '.merge' do
    it 'merges two flat configs' do
      base = { 'a' => 1, 'b' => 2 }
      override = { 'b' => 3, 'c' => 4 }

      result = described_class.merge(base, override)

      expect(result).to eq('a' => 1, 'b' => 3, 'c' => 4)
    end

    it 'deep merges sections' do
      base = { 'db' => { 'host' => 'localhost', 'port' => 5432 } }
      override = { 'db' => { 'port' => 3306, 'name' => 'mydb' } }

      result = described_class.merge(base, override)

      expect(result).to eq('db' => { 'host' => 'localhost', 'port' => 3306, 'name' => 'mydb' })
    end

    it 'replaces scalar with section' do
      base = { 'db' => 'sqlite' }
      override = { 'db' => { 'host' => 'localhost' } }

      result = described_class.merge(base, override)

      expect(result).to eq('db' => { 'host' => 'localhost' })
    end

    it 'does not modify the original hashes' do
      base = { 'db' => { 'host' => 'localhost' } }
      override = { 'db' => { 'port' => 5432 } }

      described_class.merge(base, override)

      expect(base).to eq('db' => { 'host' => 'localhost' })
      expect(override).to eq('db' => { 'port' => 5432 })
    end
  end

  describe '.diff' do
    it 'detects added global keys' do
      a = { 'name' => 'App' }
      b = { 'name' => 'App', 'version' => 2 }

      result = described_class.diff(a, b)

      expect(result[:added]).to eq('version' => 2)
      expect(result[:removed]).to be_empty
      expect(result[:changed]).to be_empty
    end

    it 'detects removed global keys' do
      a = { 'name' => 'App', 'version' => 2 }
      b = { 'name' => 'App' }

      result = described_class.diff(a, b)

      expect(result[:removed]).to eq('version' => 2)
      expect(result[:added]).to be_empty
      expect(result[:changed]).to be_empty
    end

    it 'detects changed global keys' do
      a = { 'name' => 'OldApp' }
      b = { 'name' => 'NewApp' }

      result = described_class.diff(a, b)

      expect(result[:changed]).to eq('name' => { from: 'OldApp', to: 'NewApp' })
      expect(result[:added]).to be_empty
      expect(result[:removed]).to be_empty
    end

    it 'detects added sections' do
      a = {}
      b = { 'db' => { 'host' => 'localhost' } }

      result = described_class.diff(a, b)

      expect(result[:added]).to eq('db' => { 'host' => 'localhost' })
    end

    it 'detects removed sections' do
      a = { 'db' => { 'host' => 'localhost' } }
      b = {}

      result = described_class.diff(a, b)

      expect(result[:removed]).to eq('db' => { 'host' => 'localhost' })
    end

    it 'detects added keys within sections' do
      a = { 'db' => { 'host' => 'localhost' } }
      b = { 'db' => { 'host' => 'localhost', 'port' => 5432 } }

      result = described_class.diff(a, b)

      expect(result[:added]).to eq('db' => { 'port' => 5432 })
      expect(result[:changed]).to be_empty
    end

    it 'detects removed keys within sections' do
      a = { 'db' => { 'host' => 'localhost', 'port' => 5432 } }
      b = { 'db' => { 'host' => 'localhost' } }

      result = described_class.diff(a, b)

      expect(result[:removed]).to eq('db' => { 'port' => 5432 })
    end

    it 'detects changed keys within sections' do
      a = { 'db' => { 'host' => 'localhost', 'port' => 5432 } }
      b = { 'db' => { 'host' => '127.0.0.1', 'port' => 5432 } }

      result = described_class.diff(a, b)

      expect(result[:changed]).to eq('db' => { 'host' => { from: 'localhost', to: '127.0.0.1' } })
    end

    it 'returns empty diff for identical hashes' do
      a = { 'name' => 'App', 'db' => { 'host' => 'localhost' } }
      b = { 'name' => 'App', 'db' => { 'host' => 'localhost' } }

      result = described_class.diff(a, b)

      expect(result[:added]).to be_empty
      expect(result[:removed]).to be_empty
      expect(result[:changed]).to be_empty
    end

    it 'handles mixed additions, removals, and changes' do
      a = {
        'name' => 'OldApp',
        'debug' => true,
        'db' => { 'host' => 'localhost', 'port' => 5432 }
      }
      b = {
        'name' => 'NewApp',
        'version' => 1,
        'db' => { 'host' => '10.0.0.1', 'name' => 'mydb' }
      }

      result = described_class.diff(a, b)

      expect(result[:added]).to include('version' => 1)
      expect(result[:added]['db']).to eq('name' => 'mydb')
      expect(result[:removed]).to include('debug' => true)
      expect(result[:removed]['db']).to eq('port' => 5432)
      expect(result[:changed]).to include('name' => { from: 'OldApp', to: 'NewApp' })
      expect(result[:changed]['db']).to eq('host' => { from: 'localhost', to: '10.0.0.1' })
    end
  end

  describe '.filter' do
    let(:config) do
      {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432 },
        'cache' => { 'ttl' => 60 },
        'logging' => { 'level' => 'info' }
      }
    end

    it 'returns only the named section when given a string' do
      result = described_class.filter(config, section: 'database')

      expect(result).to eq('database' => { 'host' => 'localhost', 'port' => 5432 })
    end

    it 'returns multiple sections when given an array' do
      result = described_class.filter(config, section: %w[database cache])

      expect(result).to eq(
        'database' => { 'host' => 'localhost', 'port' => 5432 },
        'cache' => { 'ttl' => 60 }
      )
    end

    it 'returns an empty hash for unknown sections' do
      result = described_class.filter(config, section: 'missing')

      expect(result).to eq({})
    end

    it 'does not mutate the input hash' do
      snapshot = config.dup
      described_class.filter(config, section: 'database')

      expect(config).to eq(snapshot)
    end

    it 'matches string keys when given a symbol section' do
      result = described_class.filter(config, section: :database)

      expect(result).to eq('database' => { 'host' => 'localhost', 'port' => 5432 })
    end

    it 'raises ArgumentError when hash is not a Hash' do
      expect { described_class.filter('not a hash', section: 'database') }.to raise_error(ArgumentError)
    end
  end

  describe '.has_section?' do
    let(:parsed) do
      described_class.parse(<<~INI)
        global = top
        [database]
        host = localhost
        [logging]
        level = info
      INI
    end

    it 'returns true for a present section' do
      expect(described_class.has_section?(parsed, 'database')).to be(true)
    end

    it 'returns true for a section name passed as a symbol' do
      expect(described_class.has_section?(parsed, :logging)).to be(true)
    end

    it 'returns false for a global key (scalar value)' do
      expect(described_class.has_section?(parsed, 'global')).to be(false)
    end

    it 'returns false for an unknown section' do
      expect(described_class.has_section?(parsed, 'missing')).to be(false)
    end

    it 'raises ArgumentError when hash is not a Hash' do
      expect { described_class.has_section?('nope', 'database') }.to raise_error(ArgumentError)
    end
  end

  describe '.sections' do
    it 'returns section names from an INI string' do
      ini = <<~INI
        name = MyApp

        [database]
        host = localhost

        [logging]
        level = info
      INI

      result = described_class.sections(ini)

      expect(result).to eq(%w[database logging])
    end

    it 'returns an empty array when there are no sections' do
      ini = "name = MyApp\nversion = 1"
      result = described_class.sections(ini)

      expect(result).to eq([])
    end

    it 'reads section names from a file path' do
      file = Tempfile.new(['test', '.ini'])
      file.write("[server]\nhost = 0.0.0.0\n\n[cache]\nttl = 60\n")
      file.close

      result = described_class.sections(file.path)

      expect(result).to eq(%w[server cache])
    ensure
      file&.unlink
    end

    it 'ignores comments and blank lines' do
      ini = <<~INI
        ; config
        # another comment

        [section1]
        key = val

        [section2]
      INI

      result = described_class.sections(ini)

      expect(result).to eq(%w[section1 section2])
    end

    it 'preserves section order' do
      ini = "[z_section]\n[a_section]\n[m_section]\n"
      result = described_class.sections(ini)

      expect(result).to eq(%w[z_section a_section m_section])
    end
  end

  describe '.valid?' do
    it 'returns true for valid INI content' do
      expect(described_class.valid?("[section]\nkey = value")).to be true
    end

    it 'returns true for empty content' do
      expect(described_class.valid?('')).to be true
    end

    it 'returns false for invalid content' do
      expect(described_class.valid?('this is not valid ini')).to be false
    end

    it 'returns true for comments only' do
      expect(described_class.valid?("; comment\n# another")).to be true
    end
  end

  describe '.get' do
    let(:config) do
      {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432 }
      }
    end

    it 'retrieves a global key' do
      expect(described_class.get(config, 'name')).to eq('MyApp')
    end

    it 'retrieves a nested key with dot path' do
      expect(described_class.get(config, 'database.host')).to eq('localhost')
    end

    it 'returns nil for missing keys' do
      expect(described_class.get(config, 'missing')).to be_nil
    end

    it 'returns nil for missing nested keys' do
      expect(described_class.get(config, 'database.missing')).to be_nil
    end

    it 'returns default for missing keys' do
      expect(described_class.get(config, 'missing', default: 'fallback')).to eq('fallback')
    end

    it 'returns default for missing nested paths' do
      expect(described_class.get(config, 'no.such.path', default: 0)).to eq(0)
    end

    it 'returns the section hash for a section path' do
      expect(described_class.get(config, 'database')).to eq('host' => 'localhost', 'port' => 5432)
    end
  end

  describe '.set' do
    it 'sets a global key' do
      config = {}
      described_class.set(config, 'name', 'MyApp')
      expect(config['name']).to eq('MyApp')
    end

    it 'sets a nested key' do
      config = { 'database' => { 'host' => 'localhost' } }
      described_class.set(config, 'database.port', 5432)
      expect(config['database']['port']).to eq(5432)
    end

    it 'creates intermediate hashes as needed' do
      config = {}
      described_class.set(config, 'database.host', 'localhost')
      expect(config).to eq('database' => { 'host' => 'localhost' })
    end

    it 'overwrites existing values' do
      config = { 'database' => { 'port' => 3306 } }
      described_class.set(config, 'database.port', 5432)
      expect(config['database']['port']).to eq(5432)
    end

    it 'replaces a scalar with a section when setting a deeper path' do
      config = { 'db' => 'sqlite' }
      described_class.set(config, 'db.host', 'localhost')
      expect(config['db']).to eq({ 'host' => 'localhost' })
    end
  end

  describe '.update' do
    it 'yields the current value, writes the block return, and returns the new value for a top-level key' do
      config = { 'name' => 'MyApp' }
      yielded = nil

      result = described_class.update(config, 'name') do |value|
        yielded = value
        'NewApp'
      end

      expect(yielded).to eq('MyApp')
      expect(result).to eq('NewApp')
      expect(config['name']).to eq('NewApp')
    end

    it 'yields the current value, writes the block return, and returns the new value for a nested key' do
      config = { 'database' => { 'host' => 'localhost', 'port' => 5432 } }
      yielded = nil

      result = described_class.update(config, 'database.port') do |value|
        yielded = value
        value + 1
      end

      expect(yielded).to eq(5432)
      expect(result).to eq(5433)
      expect(config).to eq('database' => { 'host' => 'localhost', 'port' => 5433 })
    end

    it 'returns nil and does not call the block when the path is absent' do
      config = { 'database' => { 'host' => 'localhost' } }
      snapshot = Marshal.load(Marshal.dump(config))
      call_count = 0

      result = described_class.update(config, 'database.missing') do |_value|
        call_count += 1
        'should not be written'
      end

      expect(result).to be_nil
      expect(call_count).to eq(0)
      expect(config).to eq(snapshot)
    end

    it 'raises ArgumentError when called without a block' do
      config = { 'name' => 'MyApp' }

      expect { described_class.update(config, 'name') }.to raise_error(ArgumentError, 'block required')
    end
  end

  describe 'roundtrip' do
    it 'parse then dump preserves data' do
      ini = <<~INI
        name = MyApp

        [database]
        host = localhost
        port = 5432
        ssl = true
      INI

      result = described_class.dump(described_class.parse(ini))

      reparsed = described_class.parse(result)

      expect(reparsed).to eq(
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432, 'ssl' => true }
      )
    end

    it 'roundtrips escape sequences' do
      original = { 'msg' => "hello\nworld", 'path' => 'C:\\Users', 'data' => 'a;b' }
      dumped = described_class.dump(original)
      reparsed = described_class.parse(dumped, coerce_types: false)

      expect(reparsed['msg']).to eq("hello\nworld")
      expect(reparsed['path']).to eq('C:\\Users')
      expect(reparsed['data']).to eq('a;b')
    end
  end

  describe '.flatten' do
    it 'flattens sections to dot-separated keys' do
      hash = { 'name' => 'MyApp', 'database' => { 'host' => 'localhost', 'port' => 5432 } }
      result = described_class.flatten(hash)
      expect(result).to eq({ 'name' => 'MyApp', 'database.host' => 'localhost', 'database.port' => 5432 })
    end

    it 'handles globals-only hash' do
      hash = { 'a' => 1, 'b' => 2 }
      expect(described_class.flatten(hash)).to eq({ 'a' => 1, 'b' => 2 })
    end

    it 'handles sections-only hash' do
      hash = { 'db' => { 'host' => 'localhost' } }
      expect(described_class.flatten(hash)).to eq({ 'db.host' => 'localhost' })
    end

    it 'returns empty hash for empty input' do
      expect(described_class.flatten({})).to eq({})
    end
  end

  describe '.unflatten' do
    it 'converts dot-separated keys to nested sections' do
      flat = { 'name' => 'MyApp', 'database.host' => 'localhost', 'database.port' => 5432 }
      result = described_class.unflatten(flat)
      expect(result).to eq({ 'name' => 'MyApp', 'database' => { 'host' => 'localhost', 'port' => 5432 } })
    end

    it 'handles keys without dots' do
      flat = { 'a' => 1, 'b' => 2 }
      expect(described_class.unflatten(flat)).to eq({ 'a' => 1, 'b' => 2 })
    end

    it 'returns empty hash for empty input' do
      expect(described_class.unflatten({})).to eq({})
    end

    it 'round-trips with flatten' do
      hash = { 'name' => 'MyApp', 'db' => { 'host' => 'localhost', 'port' => 5432 } }
      expect(described_class.unflatten(described_class.flatten(hash))).to eq(hash)
    end
  end

  describe '.parse with interpolate' do
    it 'expands a simple variable reference' do
      ini = "[app]\nname = MyApp\ntitle = Welcome to ${app.name}"
      result = described_class.parse(ini, interpolate: true)

      expect(result['app']['title']).to eq('Welcome to MyApp')
    end

    it 'expands multiple references in one value' do
      ini = "[db]\nhost = localhost\nport = 5432\nurl = ${db.host}:${db.port}"
      result = described_class.parse(ini, interpolate: true)

      expect(result['db']['url']).to eq('localhost:5432')
    end

    it 'expands nested references across sections' do
      ini = "[app]\nname = MyApp\n\n[logging]\nprefix = ${app.name}-log"
      result = described_class.parse(ini, interpolate: true)

      expect(result['logging']['prefix']).to eq('MyApp-log')
    end

    it 'falls back to ENV for unresolved INI references' do
      ENV['INI_TEST_FALLBACK'] = 'from_env'
      ini = 'value = ${INI_TEST_FALLBACK}'
      result = described_class.parse(ini, interpolate: true)

      expect(result['value']).to eq('from_env')
    ensure
      ENV.delete('INI_TEST_FALLBACK')
    end

    it 'leaves unresolved variables as-is' do
      ini = 'value = ${NONEXISTENT_VAR_12345}'
      result = described_class.parse(ini, interpolate: true)

      expect(result['value']).to eq('${NONEXISTENT_VAR_12345}')
    end

    it 'does not interpolate when interpolate is false' do
      ini = "[app]\nname = MyApp\ntitle = ${app.name}"
      result = described_class.parse(ini, interpolate: false)

      expect(result['app']['title']).to eq('${app.name}')
    end

    it 'interpolates global key references' do
      ini = "base = /opt\npath = ${base}/app"
      result = described_class.parse(ini, interpolate: true)

      expect(result['path']).to eq('/opt/app')
    end

    it 'handles values with no interpolation markers' do
      ini = 'name = plain value'
      result = described_class.parse(ini, interpolate: true)

      expect(result['name']).to eq('plain value')
    end

    it 'does not interpolate non-string values' do
      ini = 'port = 8080'
      result = described_class.parse(ini, interpolate: true)

      expect(result['port']).to eq(8080)
    end
  end

  describe '.parse with includes' do
    it 'includes content from another file' do
      included = Tempfile.new(['included', '.ini'])
      included.write("[database]\nhost = localhost\n")
      included.close

      ini = "name = MyApp\n@include #{included.path}"
      result = described_class.parse(ini, includes: true)

      expect(result['name']).to eq('MyApp')
      expect(result['database']['host']).to eq('localhost')
    ensure
      included&.unlink
    end

    it 'includes multiple files' do
      file_a = Tempfile.new(['a', '.ini'])
      file_a.write("[section_a]\nkey = value_a\n")
      file_a.close

      file_b = Tempfile.new(['b', '.ini'])
      file_b.write("[section_b]\nkey = value_b\n")
      file_b.close

      ini = "@include #{file_a.path}\n@include #{file_b.path}\n"
      result = described_class.parse(ini, includes: true)

      expect(result['section_a']['key']).to eq('value_a')
      expect(result['section_b']['key']).to eq('value_b')
    ensure
      file_a&.unlink
      file_b&.unlink
    end

    it 'detects circular includes and raises Error' do
      file_a = Tempfile.new(['circular_a', '.ini'])
      file_b = Tempfile.new(['circular_b', '.ini'])

      file_a.write("@include #{file_b.path}\n")
      file_a.close
      file_b.write("@include #{file_a.path}\n")
      file_b.close

      ini = "@include #{file_a.path}"

      expect { described_class.parse(ini, includes: true) }.to raise_error(
        Philiprehberger::IniParser::Error, /circular include detected/
      )
    ensure
      file_a&.unlink
      file_b&.unlink
    end

    it 'does not process includes when includes is false' do
      ini = "@include some/file.ini\nname = MyApp"

      expect { described_class.parse(ini, includes: false) }.to raise_error(
        Philiprehberger::IniParser::ParseError
      )
    end
  end

  describe '.validate' do
    it 'returns empty array for valid content' do
      ini = "[section]\nkey = value\n"
      expect(described_class.validate(ini)).to eq([])
    end

    it 'returns errors with line numbers for invalid lines' do
      ini = "key = value\nnot valid\nanother bad line"
      errors = described_class.validate(ini)

      expect(errors.length).to eq(2)
      expect(errors[0]).to eq({ line: 2, message: 'invalid line: not valid' })
      expect(errors[1]).to eq({ line: 3, message: 'invalid line: another bad line' })
    end

    it 'returns empty array for empty content' do
      expect(described_class.validate('')).to eq([])
    end

    it 'returns empty array for comments only' do
      expect(described_class.validate("; comment\n# another")).to eq([])
    end

    it 'identifies multiple errors in mixed content' do
      ini = "[section]\nkey = value\nbad line\n\n; comment\nanother bad"
      errors = described_class.validate(ini)

      expect(errors.length).to eq(2)
      expect(errors[0][:line]).to eq(3)
      expect(errors[1][:line]).to eq(6)
    end

    it 'handles continuation lines correctly' do
      ini = "key = value\\\n  continued\nbad line"
      errors = described_class.validate(ini)

      expect(errors.length).to eq(1)
      expect(errors[0][:line]).to eq(3)
    end

    it 'returns empty array for sections with no keys' do
      expect(described_class.validate("[section]\n[another]")).to eq([])
    end
  end

  describe '.to_env' do
    it 'converts global keys to uppercase' do
      hash = { 'name' => 'MyApp', 'version' => 1 }
      result = described_class.to_env(hash)

      expect(result).to eq("NAME=MyApp\nVERSION=1")
    end

    it 'converts section keys to SECTION_KEY format' do
      hash = { 'database' => { 'host' => 'localhost', 'port' => 5432 } }
      result = described_class.to_env(hash)

      expect(result).to include('DATABASE_HOST=localhost')
      expect(result).to include('DATABASE_PORT=5432')
    end

    it 'handles mixed globals and sections' do
      hash = {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost' }
      }
      result = described_class.to_env(hash)

      expect(result).to include('NAME=MyApp')
      expect(result).to include('DATABASE_HOST=localhost')
    end

    it 'returns empty string for empty hash' do
      expect(described_class.to_env({})).to eq('')
    end

    it 'handles boolean values' do
      hash = { 'flags' => { 'debug' => true, 'verbose' => false } }
      result = described_class.to_env(hash)

      expect(result).to include('FLAGS_DEBUG=true')
      expect(result).to include('FLAGS_VERBOSE=false')
    end
  end

  describe '.keys' do
    let(:config) do
      {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432 },
        'logging' => { 'level' => 'info' }
      }
    end

    it 'returns all dot-path keys when no section is given' do
      result = described_class.keys(config)
      expect(result).to eq(%w[name database.host database.port logging.level])
    end

    it 'returns keys within a specific section' do
      result = described_class.keys(config, section: 'database')
      expect(result).to eq(%w[host port])
    end

    it 'returns empty array for a missing section' do
      result = described_class.keys(config, section: 'missing')
      expect(result).to eq([])
    end

    it 'returns empty array for a non-hash section' do
      result = described_class.keys(config, section: 'name')
      expect(result).to eq([])
    end

    it 'returns empty array for empty hash' do
      expect(described_class.keys({})).to eq([])
    end

    it 'returns only global keys when there are no sections' do
      flat = { 'a' => 1, 'b' => 2 }
      expect(described_class.keys(flat)).to eq(%w[a b])
    end
  end

  describe '.has_key?' do
    let(:config) do
      {
        'name' => 'MyApp',
        'database' => { 'host' => 'localhost', 'port' => 5432 }
      }
    end

    it 'returns true for an existing global key' do
      expect(described_class.has_key?(config, 'name')).to be true
    end

    it 'returns true for an existing nested key' do
      expect(described_class.has_key?(config, 'database.host')).to be true
    end

    it 'returns true for a section key' do
      expect(described_class.has_key?(config, 'database')).to be true
    end

    it 'returns false for a missing global key' do
      expect(described_class.has_key?(config, 'missing')).to be false
    end

    it 'returns false for a missing nested key' do
      expect(described_class.has_key?(config, 'database.missing')).to be false
    end

    it 'returns false for a path through a non-hash value' do
      expect(described_class.has_key?(config, 'name.sub')).to be false
    end

    it 'returns false for empty hash' do
      expect(described_class.has_key?({}, 'any.path')).to be false
    end
  end

  describe '.delete' do
    it 'deletes a global key' do
      hash = { 'name' => 'MyApp', 'version' => '1.0' }
      result = described_class.delete(hash, 'name')
      expect(result).to eq('MyApp')
      expect(hash).to eq({ 'version' => '1.0' })
    end

    it 'deletes a nested key by dot-path' do
      hash = { 'database' => { 'host' => 'localhost', 'port' => 5432 } }
      result = described_class.delete(hash, 'database.host')
      expect(result).to eq('localhost')
      expect(hash).to eq({ 'database' => { 'port' => 5432 } })
    end

    it 'returns nil when path does not exist' do
      hash = { 'database' => { 'host' => 'localhost' } }
      expect(described_class.delete(hash, 'database.missing')).to be_nil
    end

    it 'returns nil when intermediate key does not exist' do
      hash = { 'name' => 'MyApp' }
      expect(described_class.delete(hash, 'database.host')).to be_nil
    end

    it 'returns nil for empty hash' do
      expect(described_class.delete({}, 'any.path')).to be_nil
    end
  end

  describe '.parse with interpolate_env' do
    it 'expands a ${VAR} reference from ENV' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('localhost')

      result = described_class.parse('host=${DB_HOST}', interpolate_env: true)

      expect(result['host']).to eq('localhost')
    end

    it 'uses the default when the env var is unset' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return(nil)

      result = described_class.parse('host=${DB_HOST:-localhost}', interpolate_env: true)

      expect(result['host']).to eq('localhost')
    end

    it 'uses the env value when set, ignoring the default' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('primary')

      result = described_class.parse('host=${DB_HOST:-localhost}', interpolate_env: true)

      expect(result['host']).to eq('primary')
    end

    it 'uses the default when the env var is set to an empty string' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('')

      result = described_class.parse('host=${DB_HOST:-localhost}', interpolate_env: true)

      expect(result['host']).to eq('localhost')
    end

    it 'returns empty string for an unknown var with no default' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('NO_SUCH_VAR_12345', nil).and_return(nil)

      result = described_class.parse('value=${NO_SUCH_VAR_12345}', interpolate_env: true)

      expect(result['value']).to eq('')
    end

    it 'does not interpolate when interpolate_env is disabled (default)' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('localhost')

      result = described_class.parse('host=${DB_HOST}')

      expect(result['host']).to eq('${DB_HOST}')
    end

    it 'interpolates inside quoted values' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('localhost')

      result = described_class.parse('host = "${DB_HOST}"', interpolate_env: true)

      expect(result['host']).to eq('localhost')
    end

    it 'does not interpolate section headers' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SECTION', nil).and_return('database')

      ini = "[${SECTION}]\nhost = localhost"
      result = described_class.parse(ini, interpolate_env: true)

      expect(result.keys).to eq(['${SECTION}'])
      expect(result['${SECTION}']['host']).to eq('localhost')
    end

    it 'does not interpolate keys' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KEY_NAME', nil).and_return('host')

      ini = '${KEY_NAME} = localhost'
      result = described_class.parse(ini, interpolate_env: true)

      expect(result).to have_key('${KEY_NAME}')
      expect(result['${KEY_NAME}']).to eq('localhost')
    end

    it 'trims whitespace around the default value' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('MISSING', nil).and_return(nil)

      result = described_class.parse('value=${MISSING:-  padded  }', interpolate_env: true)

      expect(result['value']).to eq('padded')
    end

    it 'expands multiple references in one value' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('HOST', nil).and_return('localhost')
      allow(ENV).to receive(:fetch).with('PORT', nil).and_return('5432')

      result = described_class.parse('url=${HOST}:${PORT}', interpolate_env: true)

      expect(result['url']).to eq('localhost:5432')
    end

    it 'treats $$ as an escape for a literal dollar sign' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('VAR', nil).and_return('resolved')

      result = described_class.parse('value=$${VAR} and ${VAR}', interpolate_env: true)

      expect(result['value']).to eq('${VAR} and resolved')
    end

    it 'interpolates values inside sections' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DB_HOST', nil).and_return('localhost')

      ini = "[database]\nhost = ${DB_HOST}"
      result = described_class.parse(ini, interpolate_env: true)

      expect(result['database']['host']).to eq('localhost')
    end
  end
end
