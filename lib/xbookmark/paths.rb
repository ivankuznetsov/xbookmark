# frozen_string_literal: true

module Xbookmark
  module Paths
    module_function

    def macos?
      RbConfig::CONFIG["host_os"] =~ /darwin/i ? true : false
    end

    def linux?
      RbConfig::CONFIG["host_os"] =~ /linux/i ? true : false
    end

    def home
      Dir.home
    end

    def xdg_config_home
      ENV["XDG_CONFIG_HOME"] || File.join(home, ".config")
    end

    def xdg_data_home
      ENV["XDG_DATA_HOME"] || File.join(home, ".local", "share")
    end

    def xdg_state_home
      ENV["XDG_STATE_HOME"] || File.join(home, ".local", "state")
    end

    def default_config_dir
      File.join(xdg_config_home, "xbookmark")
    end

    def default_wiki_dir
      if macos? && ENV["XDG_DATA_HOME"].to_s.empty?
        File.join(home, "Library", "Application Support", "xbookmark-wiki")
      else
        File.join(xdg_data_home, "xbookmark-wiki")
      end
    end

    def default_vault_dir
      default_wiki_dir
    end

    def default_logs_dir
      if macos? && ENV["XDG_STATE_HOME"].to_s.empty?
        File.join(home, "Library", "Logs", "xbookmark")
      else
        File.join(xdg_state_home, "xbookmark")
      end
    end

    def project_env_path(cwd: Dir.pwd)
      File.join(cwd, ".env")
    end

    def user_env_path
      File.join(default_config_dir, ".env")
    end
  end
end
