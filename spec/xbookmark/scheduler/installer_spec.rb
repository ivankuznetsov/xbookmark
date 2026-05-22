# frozen_string_literal: true

require "xbookmark/scheduler/installer"

RSpec.describe Xbookmark::Scheduler::Installer do
  let(:scheduler) { instance_double("Xbookmark::Scheduler::Base", install: true, uninstall: true, status: "ok") }
  let(:config) { double(daily_sync_time: "06:00") }
  subject(:installer) { described_class.new(config: config, scheduler: scheduler) }

  it "delegates install to the scheduler, defaulting time to config.daily_sync_time" do
    expect(scheduler).to receive(:install).with(time: "06:00", dry_run: false)
    installer.install
  end

  it "honors an explicit time override" do
    expect(scheduler).to receive(:install).with(time: "08:30", dry_run: true)
    installer.install(time: "08:30", dry_run: true)
  end

  it "delegates uninstall" do
    expect(scheduler).to receive(:uninstall).with(time: nil, dry_run: false)
    installer.uninstall
  end

  it "delegates status" do
    expect(installer.status).to eq("ok")
  end

  it "builds the platform scheduler via Factory when none is injected" do
    stub_platform_linux
    config = double(daily_sync_time: "06:00", logs_dir: "/tmp/logs", env_file: nil)
    real_installer = described_class.new(config: config)
    expect(real_installer.instance_variable_get(:@scheduler)).to be_a(Xbookmark::Scheduler::Systemd)
  end
end
