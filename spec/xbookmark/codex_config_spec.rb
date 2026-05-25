# frozen_string_literal: true

require "xbookmark/codex_config"

RSpec.describe Xbookmark::CodexConfig do
  it "uses CODEX_HOME when present" do
    Dir.mktmpdir do |dir|
      old_home = ENV["CODEX_HOME"]
      ENV["CODEX_HOME"] = dir

      expect(described_class.default_path).to eq(File.join(dir, "config.toml"))
    ensure
      old_home ? ENV["CODEX_HOME"] = old_home : ENV.delete("CODEX_HOME")
    end
  end

  it "does not create a codex config when no override exists" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "codex", "config.toml")

      changed = described_class.new(path: path).remove_service_tier_override!

      expect(changed).to be(false)
      expect(File.exist?(path)).to be(false)
    end
  end

  it "removes stale invalid top-level service tiers" do
    input = <<~TOML
      model = "gpt-5.5"
      service_tier = "default"
      service_tier = "flex"
      service_tier = 'default'
      [projects."/tmp/app"]
      service_tier = "default"
      trust_level = "trusted"
    TOML

    expect(described_class.without_service_tier(input)).to eq(<<~TOML)
      model = "gpt-5.5"
      [projects."/tmp/app"]
      service_tier = "default"
      trust_level = "trusted"
    TOML
  end

  it "preserves intentional valid speed tiers" do
    input = <<~TOML
      model = "gpt-5.5"
      service_tier = "fast"
    TOML

    expect(described_class.without_service_tier(input)).to eq(input)
  end

  it "leaves configs without a service tier unchanged" do
    input = <<~TOML
      model = "gpt-5.5"
      [projects."/tmp/app"]
      trust_level = "trusted"
    TOML

    expect(described_class.without_service_tier(input)).to eq(input)
  end

  it "does not rewrite a config without a service tier" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "model = \"gpt-5.5\"\n")

      changed = described_class.new(path: path).remove_service_tier_override!

      expect(changed).to be(false)
      expect(File.read(path)).to eq("model = \"gpt-5.5\"\n")
    end
  end

  it "tightens permissions on existing config files it rewrites" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "service_tier = \"default\"\n")
      File.chmod(0o644, path)

      described_class.new(path: path).remove_service_tier_override!

      expect(File.read(path)).to eq("")
      expect(format("%o", File.stat(path).mode & 0o777)).to eq("600")
    end
  end

  it "keeps the original config if atomic replacement fails" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "service_tier = \"default\"\nmodel = \"gpt-5.5\"\n")
      allow(File).to receive(:rename).and_raise(Errno::EACCES)

      expect { described_class.new(path: path).remove_service_tier_override! }.to raise_error(Errno::EACCES)
      expect(File.read(path)).to eq("service_tier = \"default\"\nmodel = \"gpt-5.5\"\n")
      expect(Dir.children(dir)).to eq(["config.toml"])
    end
  end
end
