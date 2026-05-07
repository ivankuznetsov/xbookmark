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
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\n")
      config = described_class.load(cwd: cwd, env: { "XDG_DATA_HOME" => "/data/xdg" })
      expect(config.vault_path).to eq("/data/xdg/xbookmark-vault")
    end
  end

  it "falls back to ~/.local/share on Linux when XDG_DATA_HOME is unset" do
    stub_platform_linux
    with_tmp_home do |home|
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\n")
        config = described_class.load(cwd: cwd, env: {})
        expect(config.vault_path).to eq(File.join(home, ".local", "share", "xbookmark-vault"))
      end
    end
  end

  it "uses Library/Application Support on macOS by default" do
    stub_platform_macos
    with_tmp_home do |home|
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\n")
        config = described_class.load(cwd: cwd, env: {})
        expect(config.vault_path).to eq(File.join(home, "Library", "Application Support", "xbookmark-vault"))
      end
    end
  end

  it "honors XBOOKMARK_VAULT and CLI vault override" do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, ".env"), "X_CLIENT_ID=abc\nXBOOKMARK_VAULT=/custom/vault\n")
      config = described_class.load(cwd: cwd, env: {})
      expect(config.vault_path).to eq("/custom/vault")

      override = described_class.load(cwd: cwd, env: {}, vault_override: "/override/vault")
      expect(override.vault_path).to eq("/override/vault")
    end
  end
end
