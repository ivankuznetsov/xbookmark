# frozen_string_literal: true

require "stringio"
require "xbookmark/cli"

RSpec.describe Xbookmark::CLI::Uninstall do
  let(:keystore) { Xbookmark::Keystore.new(backend: Xbookmark::Keystore::Memory.new) }
  let(:scheduler) { instance_double("Xbookmark::Scheduler::Installer", uninstall: true) }
  let(:output) { StringIO.new }

  def run_uninstall(opts = {})
    described_class.new([], {
      output: output,
      input: StringIO.new("y\n"),
      keystore: keystore,
      scheduler: scheduler
    }.merge(opts)).execute
  end

  it "refuses to run without --purge" do
    code = run_uninstall(purge: false)
    expect(code).to eq(1)
    expect(output.string).to include("pass --purge")
    expect(scheduler).not_to have_received(:uninstall)
  end

  it "tears down scheduler, keystore, and config dir when --purge --yes is given" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      keystore.set("X_CLIENT_ID", "abc")
      keystore.set("X_USER_ID", "42")

      code = run_uninstall(purge: true, yes: true)

      expect(scheduler).to have_received(:uninstall).with(dry_run: false)
      expect(keystore.list_keys).to be_empty
      expect(File.directory?(config_dir)).to be false
      expect(code).to eq(0)
    end
  end

  it "returns non-zero when confirmation is declined" do
    input = StringIO.new("n\n")

    code = run_uninstall(purge: true, yes: false, input: input)

    expect(code).to eq(1)
    expect(scheduler).not_to have_received(:uninstall)
  end

  it "continues past a scheduler failure and returns non-zero" do
    allow(scheduler).to receive(:uninstall).and_raise(StandardError, "boom")
    keystore.set("X_CLIENT_ID", "abc")
    code = run_uninstall(purge: true, yes: true)
    expect(code).to eq(1)
    expect(keystore.get("X_CLIENT_ID")).to be_nil # keystore step still ran
    expect(output.string).to include("scheduler uninstall failed: boom")
  end

  it "does not delete keystore entries during dry-run" do
    keystore.set("X_CLIENT_ID", "abc")
    code = run_uninstall(purge: true, yes: true, "dry-run": true)
    expect(code).to eq(0)
    expect(scheduler).to have_received(:uninstall).with(dry_run: true)
    expect(keystore.get("X_CLIENT_ID")).to eq("abc")
    expect(output.string).to include("would remove: x_client_id")
  end

  it "does not remove the config directory during dry-run" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      code = run_uninstall(purge: true, yes: true, "dry-run": true)

      expect(code).to eq(0)
      expect(File.directory?(config_dir)).to be true
      expect(output.string).to include("removing config directory")
    end
  end

  it "continues past a keystore deletion failure" do
    bad_keystore = instance_double("Xbookmark::Keystore")
    allow(bad_keystore).to receive(:delete_all).and_raise(StandardError, "locked")

    code = run_uninstall(purge: true, yes: true, keystore: bad_keystore)

    expect(code).to eq(1)
    expect(output.string).to include("keystore delete failed: locked")
  end

  it "continues past a config directory removal failure" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      allow(FileUtils).to receive(:rm_rf).with(config_dir).and_raise(StandardError, "permission denied")

      code = run_uninstall(purge: true, yes: true)

      expect(code).to eq(1)
      expect(output.string).to include("config rm failed: permission denied")
    end
  end

  it "builds an installer with fallback config when config loading fails" do
    fallback = instance_double("Xbookmark::Scheduler::Installer", uninstall: true)
    allow(Xbookmark::Config).to receive(:load).and_raise(StandardError, "missing secrets")
    expect(Xbookmark::Scheduler::Installer).to receive(:new) do |config:|
      expect(config.daily_sync_time).to eq("06:00")
      expect(config.env_file).to be_nil
      fallback
    end

    code = described_class.new([], output: output, input: StringIO.new, keystore: keystore,
                                   purge: true, yes: true).execute

    expect(code).to eq(0)
    expect(fallback).to have_received(:uninstall).with(dry_run: false)
  end

  it "uses a noop installer on unsupported platforms" do
    allow(Xbookmark::Config).to receive(:load).and_return(
      Struct::XbookmarkConfig.new(daily_sync_time: "06:00", logs_dir: "/tmp/logs", env_file: nil)
    )
    allow(Xbookmark::Scheduler::Installer).to receive(:new).and_raise(Xbookmark::UnsupportedPlatform, "no scheduler")

    code = described_class.new([], output: output, input: StringIO.new, keystore: keystore,
                                   purge: true, yes: true).execute

    expect(code).to eq(0)
  end

  it "is idempotent — second run after a real teardown still returns 0" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      keystore.set("X_CLIENT_ID", "abc")
      keystore.set("X_CLIENT_SECRET", "shh")
      keystore.set("X_USER_ID", "42")

      first_code = run_uninstall(purge: true, yes: true)
      expect(first_code).to eq(0)
      expect(keystore.list_keys).to be_empty
      expect(File.directory?(config_dir)).to be false

      output.truncate(0)
      output.rewind

      second_code = run_uninstall(purge: true, yes: true)
      expect(second_code).to eq(0)
      expect(output.string).to include("no keystore entries to remove")
      expect(keystore.list_keys).to be_empty
      expect(File.directory?(config_dir)).to be false
    end
  end
end
