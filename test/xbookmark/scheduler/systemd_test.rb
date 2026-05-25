# frozen_string_literal: true

require "test_helper"

require "xbookmark/scheduler/systemd"

describe Xbookmark::Scheduler::Systemd do
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
    assert_includes out, "EnvironmentFile=/home/me/.env"
    assert_match(/ExecStart=.+xbookmark sync --from-scheduler/, out)
    assert_includes out, "Type=oneshot"
    assert_includes out, "StandardOutput=append:/var/log/xbookmark/sync.log"
  end

  it "renders the systemd .timer with OnCalendar and Persistent=true" do
    sched = described_class.new(config: config)
    out = sched.render_timer(6, 0)
    assert_includes out, "OnCalendar=*-*-* 06:00:00"
    assert_includes out, "Persistent=true"
    assert_includes out, "Unit=xbookmark-sync.service"
    assert_includes out, "WantedBy=timers.target"
  end

  it "dry-run prints content to stdout and does not touch disk" do
    sched = described_class.new(config: config)
    out = capture_stdout { sched.install(time: "06:00", dry_run: true) }
    assert_match(/ExecStart=.+xbookmark sync --from-scheduler/, out)
  end

  it "enables linger during install so timers can run after logout" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      calls = []
      sched = described_class.new(config: config)
      sched.stubs(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .returns(["Linger=no\n", "", nil])
      sched.stubs(:run).with do |*argv|
        calls << argv
        true
      end.returns(true)

      err = capture_stderr { sched.install(time: "06:00") }
      assert_match(/systemd linger enabled/, err)
      assert_includes calls, ["loginctl", "enable-linger", user]
    end
  end

  it "does not enable linger when it is already enabled" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      sched = described_class.new(config: config)
      sched.stubs(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .returns(["Linger=yes\n", "", nil])
      sched.stubs(:run).returns(true)
      sched.expects(:run).with("loginctl", "enable-linger", user).never

      err = capture_stderr { sched.install(time: "06:00") }
      assert_match(/systemd timer installed/, err)
    end
  end

  it "warns with a manual command when linger cannot be enabled automatically" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      user = ENV.fetch("USER", "user")
      sched = described_class.new(config: config)
      sched.stubs(:capture)
        .with("loginctl", "show-user", user, "--property=Linger")
        .returns(["Linger=no\n", "", nil])
      sched.define_singleton_method(:run) do |*argv|
        argv.first == "loginctl" ? false : true
      end

      err = capture_stderr { sched.install(time: "06:00") }
      assert_match(/loginctl enable-linger #{Regexp.escape(user)}/, err)
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

      assert_includes out, "systemctl --user disable --now xbookmark-sync.timer"
      assert File.exist?(service)
      assert File.exist?(timer)
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
      sched.stubs(:run).with { |*argv| calls << argv; true }.returns(true)

      sched.uninstall

      refute File.exist?(service)
      refute File.exist?(timer)
      assert_includes calls, ["systemctl", "--user", "disable", "--now", described_class::TIMER]
      assert_includes calls, ["systemctl", "--user", "daemon-reload"]
    end
  end

  it "returns systemd status output" do
    sched = described_class.new(config: config)
    sched.stubs(:capture).with("systemctl", "--user", "status", described_class::TIMER)
      .returns(["active\n", "", nil])

    assert_equal "active\n", sched.status
  end

  it "warns when checking or enabling linger raises unexpectedly" do
    with_tmp_home do
      config.logs_dir = File.join(Dir.home, "logs")
      sched = described_class.new(config: config)
      sched.stubs(:capture).raises("loginctl unavailable")
      sched.define_singleton_method(:run) do |*argv|
        raise "no loginctl" if argv.first == "loginctl"

        true
      end

      err = capture_stderr { sched.install(time: "06:00") }
      assert_match(/could not enable systemd linger automatically/, err)
    end
  end

  it "uses direct Open3 capture when no test runner is stubbed" do
    sched = described_class.new(config: config)

    out, err, status = sched.send(:capture, RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'warn'")

    assert_equal "ok", out
    assert_equal "warn", err
    assert status.success?
    assert_equal true, sched.send(:run, RbConfig.ruby, "-e", "exit 0")
  end
end
