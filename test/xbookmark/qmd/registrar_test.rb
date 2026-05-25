# frozen_string_literal: true

require "test_helper"

require "xbookmark/qmd/registrar"

describe Xbookmark::Qmd::Registrar do
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
      env_file: nil, verbose: false
    )
  end

  it "is idempotent: second call detects existing registration and skips" do
    calls = []
    runner = ->(argv) {
      calls << argv
      if argv[1..2] == %w[collection list] && calls.size > 1
        ["bookmarks #{File.join(vault, 'bookmarks')}\n", "", DummyStatus.new(0)]
      elsif argv[1..2] == %w[collection list]
        ["", "", DummyStatus.new(0)]
      elsif argv[1..2] == %w[collection add]
        ["", "", DummyStatus.new(0)]
      else
        ["", "", DummyStatus.new(0)]
      end
    }

    described_class.new(config: config, runner: runner).ensure_registered!
    described_class.new(config: config, runner: runner).ensure_registered!

    register_calls = calls.count { |argv| argv[1..2] == %w[collection add] }
    assert_equal 1, register_calls
  end

  it "falls back to legacy qmd register and index commands" do
    calls = []
    runner = ->(argv) {
      calls << argv
      case argv[1..2]
      when %w[collection list], %w[collection add]
        ["", "Unknown command", DummyStatus.new(1)]
      else
        ["", "", DummyStatus.new(0)]
      end
    }

    described_class.new(config: config, runner: runner).ensure_registered!

    assert_includes calls, ["qmd", "register", "--name", "bookmarks", "--path", File.join(vault, "bookmarks")]
    assert_includes calls, ["qmd", "index", "--collection", "bookmarks"]
  end

  it "falls back to legacy list and returns false when qmd is missing" do
    legacy_runner = ->(argv) {
      if argv[1..2] == %w[collection list]
        ["", "Unknown command", DummyStatus.new(1)]
      else
        ["bookmarks #{File.join(vault, 'bookmarks')}\n", "", DummyStatus.new(0)]
      end
    }
    assert described_class.new(config: config, runner: legacy_runner).registered?

    missing_runner = ->(_argv) { raise Errno::ENOENT }
    refute described_class.new(config: config, runner: missing_runner).registered?
  end

  it "warns when both current and legacy registration fail" do
    runner = ->(_argv) { ["", "bad", DummyStatus.new(1)] }
    registrar = described_class.new(config: config, runner: runner)

    err = capture_stderr { assert_equal :failed, registrar.register! }
    assert_match(/qmd register failed: bad/, err)
  end

  it "falls back from legacy index to update and warns if update fails too" do
    update_calls = []
    update_runner = ->(argv) {
      update_calls << argv
      if argv[1] == "index"
        ["", "old index failed", DummyStatus.new(1)]
      else
        ["", "", DummyStatus.new(0)]
      end
    }
    described_class.new(config: config, runner: update_runner).index!
    assert_includes update_calls, ["qmd", "update"]

    failing_runner = ->(argv) {
      if argv[1] == "index"
        ["", "old index failed", DummyStatus.new(1)]
      else
        ["", "update failed", DummyStatus.new(1)]
      end
    }
    err = capture_stderr { described_class.new(config: config, runner: failing_runner).index! }
    assert_match(/qmd index failed: old index failed\nupdate failed/, err)
  end

  it "uses Open3 capture and integer statuses when no runner is injected" do
    registrar = described_class.new(config: config)
    out, err, status = registrar.send(:capture, RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'err'")

    assert_equal "ok", out
    assert_equal "err", err
    assert registrar.send(:status_success?, 0)
    refute registrar.send(:status_success?, 1)
    assert_predicate status, :success?
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
