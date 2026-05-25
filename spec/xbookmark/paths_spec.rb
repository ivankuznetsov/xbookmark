# frozen_string_literal: true

require "xbookmark/paths"

RSpec.describe Xbookmark::Paths do
  it "detects the current OS and exposes XDG defaults" do
    with_tmp_home do |home|
      ENV.delete("XDG_CONFIG_HOME")
      ENV.delete("XDG_DATA_HOME")
      ENV.delete("XDG_STATE_HOME")

      expect(described_class.macos?).to eq(false).or eq(true)
      expect(described_class.linux?).to eq(false).or eq(true)
      expect(described_class.home).to eq(home)
      expect(described_class.xdg_config_home).to eq(File.join(home, ".config"))
      expect(described_class.xdg_data_home).to eq(File.join(home, ".local", "share"))
      expect(described_class.xdg_state_home).to eq(File.join(home, ".local", "state"))
      expect(described_class.default_config_dir).to eq(File.join(home, ".config", "xbookmark"))
      expect(described_class.default_vault_dir).to eq(File.join(home, ".local", "share", "xbookmark-wiki"))
      expect(described_class.project_env_path(cwd: "/tmp/app")).to eq("/tmp/app/.env")
      expect(described_class.user_env_path).to eq(File.join(home, ".config", "xbookmark", ".env"))
    end
  end

  it "uses macOS Library defaults only when XDG overrides are absent" do
    with_tmp_home do |home|
      allow(described_class).to receive(:macos?).and_return(true)
      ENV.delete("XDG_DATA_HOME")
      ENV.delete("XDG_STATE_HOME")

      expect(described_class.default_wiki_dir)
        .to eq(File.join(home, "Library", "Application Support", "xbookmark-wiki"))
      expect(described_class.default_logs_dir)
        .to eq(File.join(home, "Library", "Logs", "xbookmark"))

      ENV["XDG_DATA_HOME"] = File.join(home, "data")
      ENV["XDG_STATE_HOME"] = File.join(home, "state")
      expect(described_class.default_wiki_dir).to eq(File.join(home, "data", "xbookmark-wiki"))
      expect(described_class.default_logs_dir).to eq(File.join(home, "state", "xbookmark"))
    end
  end
end
