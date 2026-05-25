# frozen_string_literal: true

require "test_helper"

require "xbookmark/paths"

describe Xbookmark::Paths do
  it "detects the current OS and exposes XDG defaults" do
    with_tmp_home do |home|
      ENV.delete("XDG_CONFIG_HOME")
      ENV.delete("XDG_DATA_HOME")
      ENV.delete("XDG_STATE_HOME")

      assert_includes [false, true], described_class.macos?
      assert_includes [false, true], described_class.linux?
      assert_equal home, described_class.home
      assert_equal File.join(home, ".config"), described_class.xdg_config_home
      assert_equal File.join(home, ".local", "share"), described_class.xdg_data_home
      assert_equal File.join(home, ".local", "state"), described_class.xdg_state_home
      assert_equal File.join(home, ".config", "xbookmark"), described_class.default_config_dir
      assert_equal File.join(home, ".local", "share", "xbookmark-wiki"), described_class.default_vault_dir
      assert_equal "/tmp/app/.env", described_class.project_env_path(cwd: "/tmp/app")
      assert_equal File.join(home, ".config", "xbookmark", ".env"), described_class.user_env_path
    end
  end

  it "uses macOS Library defaults only when XDG overrides are absent" do
    with_tmp_home do |home|
      described_class.stubs(:macos?).returns(true)
      ENV.delete("XDG_DATA_HOME")
      ENV.delete("XDG_STATE_HOME")

      assert_equal File.join(home, "Library", "Application Support", "xbookmark-wiki"),
                   described_class.default_wiki_dir
      assert_equal File.join(home, "Library", "Logs", "xbookmark"),
                   described_class.default_logs_dir

      ENV["XDG_DATA_HOME"] = File.join(home, "data")
      ENV["XDG_STATE_HOME"] = File.join(home, "state")
      assert_equal File.join(home, "data", "xbookmark-wiki"), described_class.default_wiki_dir
      assert_equal File.join(home, "state", "xbookmark"), described_class.default_logs_dir
    end
  end
end
