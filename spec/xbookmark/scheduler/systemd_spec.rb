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
      env_file: "/home/me/.env", verbose: false
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

  it "enables linger during install so timers can run after logout" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      calls = []
      sched = described_class.new(config: config)
      allow(sched).to receive(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .and_return(["Linger=no\n", "", nil])
      allow(sched).to receive(:run) do |*argv|
        calls << argv
        true
      end

      expect { sched.install(time: "06:00") }
        .to output(/systemd linger enabled/).to_stderr
      expect(calls).to include(["loginctl", "enable-linger", user])
    end
  end

  it "does not enable linger when it is already enabled" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      sched = described_class.new(config: config)
      allow(sched).to receive(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .and_return(["Linger=yes\n", "", nil])
      allow(sched).to receive(:run).and_return(true)
      expect(sched).not_to receive(:run).with("loginctl", "enable-linger", user)

      expect { sched.install(time: "06:00") }
        .to output(/systemd timer installed/).to_stderr
    end
  end

  it "warns with a manual command when linger cannot be enabled automatically" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      sched = described_class.new(config: config)
      allow(sched).to receive(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .and_return(["Linger=no\n", "", nil])
      allow(sched).to receive(:run) do |*argv|
        argv.first == "loginctl" ? false : true
      end

      expect { sched.install(time: "06:00") }
        .to output(/loginctl enable-linger #{Regexp.escape(user)}/).to_stderr
    end
  end

  it "dry-run uninstall prints intended commands without deleting unit files" do
    with_tmp_home do |home|
      service = File.join(home, ".config/systemd/user", described_class::SERVICE)
      timer = File.join(home, ".config/systemd/user", described_class::TIMER)
      FileUtils.mkdir_p(File.dirname(service))
      File.write(service, "service")
      File.write(timer, "timer")

      out = capture_stdout { described_class.new(config: config).uninstall(dry_run: true) }

      expect(out).to include("systemctl --user disable --now xbookmark-sync.timer")
      expect(File.exist?(service)).to be(true)
      expect(File.exist?(timer)).to be(true)
    end
  end

  it "uninstalls real unit files and reloads systemd" do
    with_tmp_home do |home|
      service = File.join(home, ".config/systemd/user", described_class::SERVICE)
      timer = File.join(home, ".config/systemd/user", described_class::TIMER)
      FileUtils.mkdir_p(File.dirname(service))
      File.write(service, "service")
      File.write(timer, "timer")
      calls = []
      sched = described_class.new(config: config)
      allow(sched).to receive(:run) { |*argv| calls << argv; true }

      sched.uninstall

      expect(File.exist?(service)).to be(false)
      expect(File.exist?(timer)).to be(false)
      expect(calls).to include(["systemctl", "--user", "disable", "--now", described_class::TIMER])
      expect(calls).to include(["systemctl", "--user", "daemon-reload"])
    end
  end

  it "returns systemd status output" do
    sched = described_class.new(config: config)
    allow(sched).to receive(:capture).with("systemctl", "--user", "status", described_class::TIMER)
      .and_return(["active\n", "", nil])

    expect(sched.status).to eq("active\n")
  end

  it "warns when checking or enabling linger raises unexpectedly" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      sched = described_class.new(config: config)
      allow(sched).to receive(:capture).and_raise("loginctl unavailable")
      allow(sched).to receive(:run) do |*argv|
        raise "no loginctl" if argv.first == "loginctl"

        true
      end

      expect { sched.install(time: "06:00") }
        .to output(/could not enable systemd linger automatically/).to_stderr
    end
  end

  it "uses direct Open3 capture when no test runner is stubbed" do
    sched = described_class.new(config: config)

    out, err, status = sched.send(:capture, RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'warn'")

    expect(out).to eq("ok")
    expect(err).to eq("warn")
    expect(status).to be_success
    expect(sched.send(:run, RbConfig.ruby, "-e", "exit 0")).to be(true)
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
