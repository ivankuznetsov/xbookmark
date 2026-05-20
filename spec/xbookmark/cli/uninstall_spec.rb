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

  it "continues past a scheduler failure and returns non-zero" do
    allow(scheduler).to receive(:uninstall).and_raise(StandardError, "boom")
    keystore.set("X_CLIENT_ID", "abc")
    code = run_uninstall(purge: true, yes: true)
    expect(code).to eq(1)
    expect(keystore.get("X_CLIENT_ID")).to be_nil # keystore step still ran
    expect(output.string).to include("scheduler uninstall failed: boom")
  end

  it "is idempotent — second run with everything already gone returns 0" do
    code = run_uninstall(purge: true, yes: true)
    expect(code).to eq(0)
  end
end
