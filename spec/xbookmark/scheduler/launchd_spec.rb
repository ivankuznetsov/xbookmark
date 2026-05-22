# frozen_string_literal: true

require "xbookmark/scheduler/launchd"

RSpec.describe Xbookmark::Scheduler::Launchd do
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
    expect(plist).to include("<string>io.xbookmark.sync</string>")
    expect(plist).to include("<string>sync</string>")
    expect(plist).to include("<string>--from-scheduler</string>")
    expect(plist).to include("<key>Hour</key><integer>6</integer>")
    expect(plist).to include("<key>Minute</key><integer>30</integer>")
    expect(plist).to include("<key>StandardOutPath</key>")
    expect(plist).to include("/Users/me/Library/Logs/xbookmark/sync.log")
  end

  it "rejects out-of-range times like 99:99 at parse time" do
    sched = described_class.new(config: config)
    expect { sched.install(time: "99:99", dry_run: true) }
      .to raise_error(Xbookmark::Error, /invalid time/)
    expect { sched.install(time: "24:00", dry_run: true) }
      .to raise_error(Xbookmark::Error, /invalid time/)
    expect { sched.install(time: "12:60", dry_run: true) }
      .to raise_error(Xbookmark::Error, /invalid time/)
  end

  it "dry-run prints the plist path and content without touching LaunchAgents" do
    with_tmp_home do |home|
      sched = described_class.new(config: config)

      out = capture_stdout { sched.install(time: "06:30", dry_run: true) }

      expect(out).to include(File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist"))
      expect(out).to include("<key>Hour</key><integer>6</integer>")
    end
  end

  it "writes and loads the launch agent during install" do
    with_tmp_home do |home|
      config.logs_dir = File.join(home, "logs")
      config.env_file = File.join(home, ".env")
      calls = []
      sched = described_class.new(config: config)
      allow(sched).to receive(:system) { |*argv| calls << argv; true }

      err = capture_stderr { sched.install(time: "06:30") }
      plist_path = File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist")

      expect(File.read(plist_path)).to include("XBOOKMARK_ENV_FILE")
      expect(File.read(plist_path)).to include(CGI.escapeHTML(config.env_file))
      expect(calls).to include(["launchctl", "unload", plist_path])
      expect(calls).to include(["launchctl", "load", "-w", plist_path])
      expect(err).to include("launchd agent installed")
    end
  end

  it "uninstalls in dry-run and real modes and reports launchctl status output" do
    with_tmp_home do |home|
      plist_path = File.join(home, "Library/LaunchAgents", "io.xbookmark.sync.plist")
      FileUtils.mkdir_p(File.dirname(plist_path))
      File.write(plist_path, "plist")
      sched = described_class.new(config: config)
      allow(sched).to receive(:system).with("launchctl", "unload", plist_path).and_return(true)

      out = capture_stdout { sched.uninstall(dry_run: true) }
      expect(out).to include("launchctl unload #{plist_path}")
      expect(File.exist?(plist_path)).to be(true)

      sched.uninstall
      expect(File.exist?(plist_path)).to be(false)
      allow(sched).to receive(:`).with("launchctl list | grep #{described_class::LABEL}").and_return("123\t#{described_class::LABEL}\n")
      expect(sched.status).to eq("123\t#{described_class::LABEL}\n")
    end
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end
end
