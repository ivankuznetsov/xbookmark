# frozen_string_literal: true

require "test_helper"

require "xbookmark/scheduler/launchd"

describe Xbookmark::Scheduler::Launchd do
  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: "/v", state_db_path: ":memory:",
      logs_dir: "/Users/me/Library/Logs/xbookmark",
      scratch_dir: "/v/.xbookmark/scratch",
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      env_file: nil, verbose: false
    )
  end

  it "renders a launchd plist with StartCalendarInterval at the configured time" do
    plist = described_class.new(config: config).render_plist(6, 30)
    assert_includes plist, "<string>io.xbookmark.sync</string>"
    assert_includes plist, "<string>sync</string>"
    assert_includes plist, "<string>--from-scheduler</string>"
    assert_includes plist, "<key>Hour</key><integer>6</integer>"
    assert_includes plist, "<key>Minute</key><integer>30</integer>"
    assert_includes plist, "<key>StandardOutPath</key>"
    assert_includes plist, "/Users/me/Library/Logs/xbookmark/sync.log"
  end

  it "rejects out-of-range times like 99:99 at parse time" do
    sched = described_class.new(config: config)
    error = assert_raises(Xbookmark::Error) { sched.install(time: "99:99", dry_run: true) }
    assert_match(/invalid time/, error.message)
    error = assert_raises(Xbookmark::Error) { sched.install(time: "24:00", dry_run: true) }
    assert_match(/invalid time/, error.message)
    error = assert_raises(Xbookmark::Error) { sched.install(time: "12:60", dry_run: true) }
    assert_match(/invalid time/, error.message)
  end

  it "dry-run prints the plist path and content without touching LaunchAgents" do
    with_tmp_home do |home|
      sched = described_class.new(config: config)

      out = capture_stdout { sched.install(time: "06:30", dry_run: true) }

      assert_includes out, File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist")
      assert_includes out, "<key>Hour</key><integer>6</integer>"
    end
  end

  it "writes and loads the launch agent during install" do
    with_tmp_home do |home|
      config.logs_dir = File.join(home, "logs")
      config.env_file = File.join(home, ".env")
      calls = []
      sched = described_class.new(config: config)
      sched.stubs(:system).with { |*argv| calls << argv; true }.returns(true)

      err = capture_stderr { sched.install(time: "06:30") }
      plist_path = File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist")

      assert_includes File.read(plist_path), "XBOOKMARK_ENV_FILE"
      assert_includes File.read(plist_path), CGI.escapeHTML(config.env_file)
      assert_includes calls, ["launchctl", "unload", plist_path]
      assert_includes calls, ["launchctl", "load", "-w", plist_path]
      assert_includes err, "launchd agent installed"
    end
  end

  it "uninstalls in dry-run and real modes and reports launchctl status output" do
    with_tmp_home do |home|
      plist_path = File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist")
      FileUtils.mkdir_p(File.dirname(plist_path))
      File.write(plist_path, "plist")
      sched = described_class.new(config: config)
      sched.stubs(:system).with("launchctl", "unload", plist_path).returns(true)

      out = capture_stdout { sched.uninstall(dry_run: true) }
      assert_includes out, "launchctl unload #{plist_path}"
      assert File.exist?(plist_path)

      sched.uninstall
      refute File.exist?(plist_path)
      sched.stubs(:`).with("launchctl list | grep #{described_class::LABEL}").returns("123\t#{described_class::LABEL}\n")
      assert_equal "123\t#{described_class::LABEL}\n", sched.status
    end
  end
end
