# frozen_string_literal: true

require "xbookmark/scheduler/systemd"

RSpec.describe Xbookmark::Scheduler::Systemd do
  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: "/v", state_db_path: ":memory:", logs_dir: "/var/log/xbookmark",
      scratch_dir: "/v/.xbookmark/scratch",
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      concurrency: 1, env_file: "/home/me/.env", verbose: false
    )
  end

  it "renders the systemd .service unit with EnvironmentFile and ExecStart" do
    sched = described_class.new(config: config)
    out = sched.render_service
    expect(out).to include("EnvironmentFile=/home/me/.env")
    expect(out).to match(/ExecStart=.+xbookmark sync --from-scheduler/)
    expect(out).to include("Type=oneshot")
    expect(out).to include("StandardOutput=append:/var/log/xbookmark/sync.log")
  end

  it "renders the systemd .timer with OnCalendar and Persistent=true" do
    sched = described_class.new(config: config)
    out = sched.render_timer(6, 0)
    expect(out).to include("OnCalendar=*-*-* 06:00:00")
    expect(out).to include("Persistent=true")
    expect(out).to include("Unit=xbookmark-sync.service")
    expect(out).to include("WantedBy=timers.target")
  end

  it "dry-run prints content to stdout and does not touch disk" do
    sched = described_class.new(config: config)
    expect { sched.install(time: "06:00", dry_run: true) }
      .to output(/ExecStart=.+xbookmark sync --from-scheduler/).to_stdout
  end
end
