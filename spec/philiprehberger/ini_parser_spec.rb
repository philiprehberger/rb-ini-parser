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
  end
end
