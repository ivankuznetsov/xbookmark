# frozen_string_literal: true

RSpec.describe Xbookmark::Config do
  it "loads required keys from a project .env" do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc123\nX_USER_ID=42\n")
      config = described_class.load(cwd: cwd, env: {})
      expect(config.x_client_id).to eq("abc123")
      expect(config.x_user_id).to eq("42")
      expect(config.env_file).to end_with(".env")
    end
  end

  it "raises ConfigError when X_CLIENT_ID is missing" do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "FOO=bar\n")
      expect { described_class.load(cwd: cwd, env: {}) }.to raise_error(Xbookmark::ConfigError, /X_CLIENT_ID/)
    end
  end

  it "uses XDG_DATA_HOME on Linux when set" do
    stub_platform_linux
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\n")
      config = described_class.load(cwd: cwd, env: { "XDG_DATA_HOME" => "/data/xdg" })
      expect(config.vault_path).to eq("/data/xdg/xbookmark-wiki")
    end
  end

  it "falls back to ~/.local/share on Linux when XDG_DATA_HOME is unset" do
    stub_platform_linux
    with_tmp_home do |home|
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\n")
        config = described_class.load(cwd: cwd, env: {})
        expect(config.vault_path).to eq(File.join(home, ".local", "share", "xbookmark-wiki"))
      end
    end
  end

  it "uses Library/Application Support on macOS by default" do
    stub_platform_macos
    with_tmp_home do |home|
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\n")
        config = described_class.load(cwd: cwd, env: {})
        expect(config.vault_path).to eq(File.join(home, "Library", "Application Support", "xbookmark-wiki"))
      end
    end
  end

  it "honors XBOOKMARK_WIKI_PATH and CLI bookmark wiki override" do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\nXBOOKMARK_WIKI_PATH=/custom/wiki\n")
      config = described_class.load(cwd: cwd, env: {})
      expect(config.vault_path).to eq("/custom/wiki")

      File.write(File.join(cwd, ".env"), <<~ENV)
        X_CLIENT_ID=abc
        X_USER_ID=42
        XBOOKMARK_WIKI_PATH=/new/wiki
        XBOOKMARK_VAULT=/legacy/vault
        OBSIDIAN_VAULT_PATH=/legacy/obsidian
      ENV
      precedence = described_class.load(cwd: cwd, env: {})
      expect(precedence.vault_path).to eq("/new/wiki")

      override = described_class.load(cwd: cwd, env: {}, wiki_override: "/override/wiki", vault_override: "/override/vault")
      expect(override.vault_path).to eq("/override/wiki")
    end
  end

  it "keeps older vault-named path keys as compatibility aliases" do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\nXBOOKMARK_VAULT=/legacy/vault\n")
      config = described_class.load(cwd: cwd, env: {})
      expect(config.vault_path).to eq("/legacy/vault")

      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\nOBSIDIAN_VAULT_PATH=/legacy/obsidian\n")
      obsidian = described_class.load(cwd: cwd, env: {})
      expect(obsidian.vault_path).to eq("/legacy/obsidian")

      override = described_class.load(cwd: cwd, env: {}, vault_override: "/override/vault")
      expect(override.vault_path).to eq("/override/vault")
    end
  end

  it "ignores blank wiki path values when falling back" do
    stub_platform_linux
    with_tmp_home do |home|
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\nXBOOKMARK_WIKI_PATH=\nXBOOKMARK_VAULT=/legacy/vault\n")
        legacy = described_class.load(cwd: cwd, env: {})
        expect(legacy.vault_path).to eq("/legacy/vault")

        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nX_USER_ID=42\nXBOOKMARK_WIKI_PATH=\nXBOOKMARK_VAULT=\nOBSIDIAN_VAULT_PATH=\n")
        default = described_class.load(cwd: cwd, env: {})
        expect(default.vault_path).to eq(File.join(home, ".local", "share", "xbookmark-wiki"))

        override = described_class.load(cwd: cwd, env: {}, wiki_override: "", vault_override: "/override/vault")
        expect(override.vault_path).to eq("/override/vault")
      end
    end
  end
end
