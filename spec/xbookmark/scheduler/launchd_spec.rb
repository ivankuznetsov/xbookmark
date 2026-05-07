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
      concurrency: 1, env_file: nil, verbose: false
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
end
