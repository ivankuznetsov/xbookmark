# frozen_string_literal: true

require "test_helper"

require "xbookmark/codex_config"

describe Xbookmark::CodexConfig do
  it "uses CODEX_HOME when present" do
    Dir.mktmpdir do |dir|
      old_home = ENV["CODEX_HOME"]
      ENV["CODEX_HOME"] = dir

      assert_equal File.join(dir, "config.toml"), described_class.default_path
    ensure
      old_home ? ENV["CODEX_HOME"] = old_home : ENV.delete("CODEX_HOME")
    end
  end

  it "does not create a codex config when no override exists" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "codex", "config.toml")

      changed = described_class.new(path: path).remove_service_tier_override!

      refute changed
      refute File.exist?(path)
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

    assert_equal <<~TOML, described_class.without_service_tier(input)
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

    assert_equal input, described_class.without_service_tier(input)
  end

  it "leaves configs without a service tier unchanged" do
    input = <<~TOML
      model = "gpt-5.5"
      [projects."/tmp/app"]
      trust_level = "trusted"
    TOML

    assert_equal input, described_class.without_service_tier(input)
  end

  it "does not rewrite a config without a service tier" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "model = \"gpt-5.5\"\n")

      changed = described_class.new(path: path).remove_service_tier_override!

      refute changed
      assert_equal "model = \"gpt-5.5\"\n", File.read(path)
    end
  end

  it "tightens permissions on existing config files it rewrites" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "service_tier = \"default\"\n")
      File.chmod(0o644, path)

      described_class.new(path: path).remove_service_tier_override!

      assert_equal "", File.read(path)
      assert_equal "600", format("%o", File.stat(path).mode & 0o777)
    end
  end

  it "keeps the original config if atomic replacement fails" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      File.write(path, "service_tier = \"default\"\nmodel = \"gpt-5.5\"\n")
      File.stubs(:rename).raises(Errno::EACCES)

      assert_raises(Errno::EACCES) { described_class.new(path: path).remove_service_tier_override! }
      assert_equal "service_tier = \"default\"\nmodel = \"gpt-5.5\"\n", File.read(path)
      assert_equal ["config.toml"], Dir.children(dir)
    end
  end
end
