# frozen_string_literal: true

require "dotenv"

module Xbookmark
  class Config
    REQUIRED_KEYS = %w[X_CLIENT_ID].freeze

    Struct.new(
      "XbookmarkConfig",
      :vault_path,
      :state_db_path,
      :logs_dir,
      :scratch_dir,
      :x_client_id,
      :x_client_secret,
      :x_redirect_uri,
      :x_user_id,
      :x_access_token,
      :x_refresh_token,
      :x_token_expires_at,
      :codex_bin,
      :whisper_bin,
      :whisper_model,
      :qmd_bin,
      :daily_sync_time,
      :min_run_interval_hours,
      :concurrency,
      :env_file,
      :verbose,
      keyword_init: true
    ) unless defined?(Struct::XbookmarkConfig)

    class << self
      def load(vault_override: nil, cwd: Dir.pwd, env: ENV.to_h.dup, verbose: false)
        loaded_env_files = load_env_files!(cwd: cwd, env: env)
        merged = env

        validate_required!(merged)

        vault_path = vault_override || merged["XBOOKMARK_VAULT"] || default_vault_dir(merged)
        vault_path = File.expand_path(vault_path)

        state_db_path = File.join(vault_path, ".xbookmark", "state.db")
        scratch_dir   = File.join(vault_path, ".xbookmark", "scratch")
        logs_dir      = merged["XBOOKMARK_LOGS_DIR"] || default_logs_dir(merged)

        Struct::XbookmarkConfig.new(
          vault_path: vault_path,
          state_db_path: state_db_path,
          logs_dir: File.expand_path(logs_dir),
          scratch_dir: scratch_dir,
          x_client_id: merged["X_CLIENT_ID"],
          x_client_secret: merged["X_CLIENT_SECRET"],
          x_redirect_uri: merged["X_REDIRECT_URI"] || "http://127.0.0.1:7799/callback",
          x_user_id: merged["X_USER_ID"],
          x_access_token: merged["X_ACCESS_TOKEN"],
          x_refresh_token: merged["X_REFRESH_TOKEN"],
          x_token_expires_at: parse_int_or_nil(merged["X_TOKEN_EXPIRES_AT"]),
          codex_bin: merged["CODEX_BIN"] || "codex",
          whisper_bin: merged["WHISPER_BIN"],
          whisper_model: merged["WHISPER_MODEL"] || "base.en",
          qmd_bin: merged["QMD_BIN"] || "qmd",
          daily_sync_time: merged["XBOOKMARK_DAILY_TIME"] || "06:00",
          min_run_interval_hours: (merged["XBOOKMARK_MIN_RUN_INTERVAL_HOURS"] || "20").to_f,
          concurrency: (merged["XBOOKMARK_CONCURRENCY"] || "3").to_i,
          env_file: loaded_env_files.first,
          verbose: verbose
        )
      end

      def load_env_files!(cwd:, env:)
        candidates = [
          Paths.project_env_path(cwd: cwd),
          Paths.user_env_path
        ].uniq

        loaded = []
        candidates.each do |path|
          next unless File.file?(path)
          parsed = ::Dotenv.parse(path)
          parsed.each do |k, v|
            env[k] = v unless env.key?(k)
          end
          loaded << path
        end
        loaded
      end

      def validate_required!(env)
        missing = REQUIRED_KEYS.reject { |k| env[k] && !env[k].to_s.strip.empty? }
        return if missing.empty?
        raise ConfigError, "Missing required env keys: #{missing.join(", ")}. " \
          "Copy .env.example to .env and fill in the values."
      end

      def parse_int_or_nil(value)
        return nil if value.nil? || value.to_s.strip.empty?
        Integer(value)
      rescue ArgumentError
        nil
      end

      def default_vault_dir(env)
        if Paths.macos? && env["XDG_DATA_HOME"].to_s.empty?
          File.join(Paths.home, "Library", "Application Support", "xbookmark-vault")
        elsif env["XDG_DATA_HOME"] && !env["XDG_DATA_HOME"].to_s.empty?
          File.join(env["XDG_DATA_HOME"], "xbookmark-vault")
        else
          File.join(Paths.home, ".local", "share", "xbookmark-vault")
        end
      end

      def default_logs_dir(env)
        if Paths.macos? && env["XDG_STATE_HOME"].to_s.empty?
          File.join(Paths.home, "Library", "Logs", "xbookmark")
        elsif env["XDG_STATE_HOME"] && !env["XDG_STATE_HOME"].to_s.empty?
          File.join(env["XDG_STATE_HOME"], "xbookmark")
        else
          File.join(Paths.home, ".local", "state", "xbookmark")
        end
      end
    end
  end
end
