# frozen_string_literal: true

require "xbookmark/qmd/registrar"

RSpec.describe Xbookmark::Qmd::Registrar do
  let(:vault) { Dir.mktmpdir }
  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: vault, state_db_path: ":memory:", logs_dir: "/tmp",
      scratch_dir: "#{vault}/.xbookmark/scratch",
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      concurrency: 1, env_file: nil, verbose: false
    )
  end

  it "is idempotent: second call detects existing registration and skips" do
    calls = []
    runner = ->(argv) {
      calls << argv
      if argv[1] == "list" && calls.size > 1
        ["bookmarks #{File.join(vault, 'bookmarks')}\n", "", DummyStatus.new(0)]
      elsif argv[1] == "list"
        ["", "", DummyStatus.new(0)]
      elsif argv[1] == "register" || argv[1] == "index"
        ["", "", DummyStatus.new(0)]
      else
        ["", "", DummyStatus.new(0)]
      end
    }

    described_class.new(config: config, runner: runner).ensure_registered!
    described_class.new(config: config, runner: runner).ensure_registered!

    register_calls = calls.count { |argv| argv[1] == "register" }
    expect(register_calls).to eq(1)
  end

  DummyStatus = Struct.new(:exit_status) do
    def success?
      exit_status.zero?
    end
    def exitstatus
      exit_status
    end
  end
end
