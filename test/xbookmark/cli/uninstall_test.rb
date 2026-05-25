# frozen_string_literal: true

require "test_helper"

require "stringio"
require "xbookmark/cli"

describe Xbookmark::CLI::Uninstall do
  let(:keystore) { Xbookmark::Keystore.new(backend: Xbookmark::Keystore::Memory.new) }
  let(:scheduler) { mock("scheduler").tap { |mock| mock.stubs(:uninstall).returns(true) } }
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
    scheduler.expects(:uninstall).never

    code = run_uninstall(purge: false)

    assert_equal 1, code
    assert_includes output.string, "pass --purge"
  end

  it "tears down scheduler, keystore, and config dir when --purge --yes is given" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      keystore.set("X_CLIENT_ID", "abc")
      keystore.set("X_USER_ID", "42")
      scheduler.expects(:uninstall).with(dry_run: false).returns(true)

      code = run_uninstall(purge: true, yes: true)

      assert_empty keystore.list_keys
      refute File.directory?(config_dir)
      assert_equal 0, code
    end
  end

  it "returns non-zero when confirmation is declined" do
    input = StringIO.new("n\n")
    scheduler.expects(:uninstall).never

    code = run_uninstall(purge: true, yes: false, input: input)

    assert_equal 1, code
  end

  it "continues past a scheduler failure and returns non-zero" do
    scheduler.stubs(:uninstall).raises(StandardError, "boom")
    keystore.set("X_CLIENT_ID", "abc")
    code = run_uninstall(purge: true, yes: true)
    assert_equal 1, code
    assert_nil keystore.get("X_CLIENT_ID") # keystore step still ran
    assert_includes output.string, "scheduler uninstall failed: boom"
  end

  it "does not delete keystore entries during dry-run" do
    keystore.set("X_CLIENT_ID", "abc")
    scheduler.expects(:uninstall).with(dry_run: true).returns(true)

    code = run_uninstall(purge: true, yes: true, "dry-run": true)
    assert_equal 0, code
    assert_equal "abc", keystore.get("X_CLIENT_ID")
    assert_includes output.string, "would remove: x_client_id"
  end

  it "does not remove the config directory during dry-run" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      code = run_uninstall(purge: true, yes: true, "dry-run": true)

      assert_equal 0, code
      assert File.directory?(config_dir)
      assert_includes output.string, "removing config directory"
    end
  end

  it "continues past a keystore deletion failure" do
    bad_keystore = mock("bad keystore")
    bad_keystore.stubs(:delete_all).raises(StandardError, "locked")

    code = run_uninstall(purge: true, yes: true, keystore: bad_keystore)

    assert_equal 1, code
    assert_includes output.string, "keystore delete failed: locked"
  end

  it "continues past a config directory removal failure" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      FileUtils.stubs(:rm_rf).with(config_dir).raises(StandardError, "permission denied")

      code = run_uninstall(purge: true, yes: true)

      assert_equal 1, code
      assert_includes output.string, "config rm failed: permission denied"
    end
  end

  it "builds an installer with fallback config when config loading fails" do
    fallback = mock("fallback scheduler")
    fallback.expects(:uninstall).with(dry_run: false).returns(true)
    Xbookmark::Config.stubs(:load).raises(StandardError, "missing secrets")
    Xbookmark::Scheduler::Installer.expects(:new).with do |kwargs|
      config = kwargs[:config]
      assert_equal "06:00", config.daily_sync_time
      assert_nil config.env_file
      true
    end.returns(fallback)

    code = described_class.new([], output: output, input: StringIO.new, keystore: keystore,
                                   purge: true, yes: true).execute

    assert_equal 0, code
  end

  it "uses a noop installer on unsupported platforms" do
    Xbookmark::Config.stubs(:load).returns(
      Struct::XbookmarkConfig.new(daily_sync_time: "06:00", logs_dir: "/tmp/logs", env_file: nil)
    )
    Xbookmark::Scheduler::Installer.stubs(:new).raises(Xbookmark::UnsupportedPlatform, "no scheduler")

    code = described_class.new([], output: output, input: StringIO.new, keystore: keystore,
                                   purge: true, yes: true).execute

    assert_equal 0, code
  end

  it "is idempotent - second run after a real teardown still returns 0" do
    with_tmp_home do |home|
      config_dir = File.join(home, ".config", "xbookmark")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "marker"), "x")

      keystore.set("X_CLIENT_ID", "abc")
      keystore.set("X_CLIENT_SECRET", "shh")
      keystore.set("X_USER_ID", "42")

      first_code = run_uninstall(purge: true, yes: true)
      assert_equal 0, first_code
      assert_empty keystore.list_keys
      refute File.directory?(config_dir)

      output.truncate(0)
      output.rewind

      second_code = run_uninstall(purge: true, yes: true)
      assert_equal 0, second_code
      assert_includes output.string, "no keystore entries to remove"
      assert_empty keystore.list_keys
      refute File.directory?(config_dir)
    end
  end
end
