# frozen_string_literal: true

require "test_helper"

require "xbookmark/scheduler/installer"

describe Xbookmark::Scheduler::Installer do
  let(:scheduler) { mock("scheduler") }
  let(:config) { stub(daily_sync_time: "06:00") }
  let(:installer) { described_class.new(config: config, scheduler: scheduler) }

  it "delegates install to the scheduler, defaulting time to config.daily_sync_time" do
    scheduler.expects(:install).with(time: "06:00", dry_run: false)
    installer.install
  end

  it "honors an explicit time override" do
    scheduler.expects(:install).with(time: "08:30", dry_run: true)
    installer.install(time: "08:30", dry_run: true)
  end

  it "delegates uninstall" do
    scheduler.expects(:uninstall).with(time: nil, dry_run: false)
    installer.uninstall
  end

  it "delegates status" do
    scheduler.expects(:status).returns("ok")
    assert_equal "ok", installer.status
  end

  it "builds the platform scheduler via Factory when none is injected" do
    stub_platform_linux
    config = stub(daily_sync_time: "06:00", logs_dir: "/tmp/logs", env_file: nil)
    real_installer = described_class.new(config: config)
    assert_kind_of Xbookmark::Scheduler::Systemd, real_installer.instance_variable_get(:@scheduler)
  end
end
