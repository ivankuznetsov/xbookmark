# frozen_string_literal: true

require "stringio"
require "xbookmark/cli"

RSpec.describe Xbookmark::CLI::Setup do
  let(:keystore) { Xbookmark::Keystore.new(backend: Xbookmark::Keystore::Memory.new) }
  let(:input_lines) { [] }
  let(:input) do
    str = input_lines.map { |l| "#{l}\n" }.join
    io = StringIO.new(str)
    def io.tty?; true; end
    io
  end
  let(:output) { StringIO.new }
  let(:scheduler) { instance_double("Xbookmark::Scheduler::Installer", install: true) }

  before do
    allow(Xbookmark::Paths).to receive(:project_env_path).and_return("/nonexistent-project-env")
    allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent-user-env")
  end

  def run_setup(extra = {})
    described_class.new([], {
      input: input,
      output: output,
      keystore: keystore,
      scheduler: scheduler,
      force_interactive: true
    }.merge(extra)).execute
  end

  it "prompts for every REQUIRED_KEY when keystore is empty" do
    input_lines.replace(["abc", "42", "secret", ""])
    run_setup
    expect(keystore.get("X_CLIENT_ID")).to eq("abc")
    expect(keystore.get("X_USER_ID")).to eq("42")
    expect(keystore.get("X_CLIENT_SECRET")).to eq("secret")
    expect(keystore.get("X_REDIRECT_URI")).to be_nil # empty input skipped
  end

  it "reads secret prompts through noecho when the input supports it" do
    lines = ["abc\n", "42\n", "secret\n", "\n"]
    secret_input = Object.new
    secret_input.define_singleton_method(:tty?) { true }
    secret_input.define_singleton_method(:gets) { lines.shift }
    secret_input.define_singleton_method(:noecho) { |&block| block.call(self) }

    described_class.new([], {
      input: secret_input,
      output: output,
      keystore: keystore,
      scheduler: scheduler,
      force_interactive: true
    }).execute

    expect(keystore.get("X_CLIENT_SECRET")).to eq("secret")
  end

  it "raises when a required prompt is left blank" do
    input_lines.replace([""])

    expect { run_setup }.to raise_error(Xbookmark::ConfigError, /X_CLIENT_ID/)
  end

  it "skips prompts for keys already set" do
    keystore.set("X_CLIENT_ID", "preset")
    keystore.set("X_USER_ID", "preset")
    input_lines.replace(["", ""]) # skip optionals
    run_setup
    expect(output.string).to include("X_CLIENT_ID: already set (skipping)")
    expect(output.string).to include("X_USER_ID: already set (skipping)")
  end

  it "imports a legacy .env when present" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=from-env\nX_USER_ID=99\n")
      allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

      # answers: import? yes, delete file? no, optionals empty
      input_lines.replace(["y", "n", "", ""])
      run_setup
      expect(keystore.get("X_CLIENT_ID")).to eq("from-env")
      expect(keystore.get("X_USER_ID")).to eq("99")
      expect(File.file?(env_path)).to be true # not deleted
    end
  end

  it "continues when a legacy .env has no importable keys" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "UNUSED=bar\n")
      allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

      input_lines.replace(["maybe", "abc", "42", "", ""])
      run_setup

      expect(output.string).to include("no known keys found")
      expect(keystore.get("X_CLIENT_ID")).to eq("abc")
    end
  end

  it "deletes legacy .env after a successful import when user agrees" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=from-env\nX_USER_ID=99\n")
      allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

      input_lines.replace(["y", "y", "", ""])
      run_setup
      expect(File.file?(env_path)).to be false
    end
  end

  it "installs the scheduler after setup without another prompt" do
    input_lines.replace(["abc", "42", "", ""])
    expect(scheduler).to receive(:install)
    run_setup
  end

  it "reports scheduler installation failures without failing setup" do
    input_lines.replace(["abc", "42", "", ""])
    allow(scheduler).to receive(:install).and_raise(StandardError, "no scheduler")

    expect(run_setup).to eq(0)
    expect(output.string).to include("scheduler install failed: no scheduler")
  end

  it "skips entirely in non-interactive shells" do
    non_tty = StringIO.new("")
    def non_tty.tty?; false; end

    out = StringIO.new
    described_class.new([], {
      input: non_tty,
      output: out,
      keystore: keystore,
      scheduler: scheduler
    }).execute

    expect(out.string).to include("non-interactive shell")
    expect(keystore.list_keys).to be_empty
  end

  it "treats tty probe errors as non-interactive" do
    broken_input = Object.new
    broken_input.define_singleton_method(:tty?) { raise "bad tty" }

    described_class.new([], {
      input: broken_input,
      output: output,
      keystore: keystore,
      scheduler: scheduler,
      force_interactive: true
    }).execute

    expect(output.string).to include("non-interactive shell")
  end

  describe ".first_run_check!" do
    it "returns 0 without launching the wizard when keystore is configured" do
      keystore.set("X_CLIENT_ID", "abc")
      keystore.set("X_USER_ID", "42")
      input_io = StringIO.new("")
      def input_io.tty?; true; end
      out = StringIO.new
      expect(described_class.first_run_check!(input: input_io, output: out, keystore: keystore)).to eq(0)
      expect(out.string).to be_empty
    end

    it "returns 0 without launching the wizard when stdin is not a tty" do
      input_io = StringIO.new("")
      def input_io.tty?; false; end
      out = StringIO.new
      expect(described_class.first_run_check!(input: input_io, output: out, keystore: keystore)).to eq(0)
    end

    it "launches setup when required keys are missing and stdin is a tty" do
      input_lines.replace(["abc", "42", "", ""])
      out = StringIO.new
      config = Struct::XbookmarkConfig.new(daily_sync_time: "06:00", logs_dir: "/tmp/logs", env_file: nil)
      allow(Xbookmark::Config).to receive(:load).and_return(config)
      allow(Xbookmark::Scheduler::Installer).to receive(:new).and_return(scheduler)

      old_test_env = ENV.delete("XBOOKMARK_TEST")
      begin
        expect(described_class.first_run_check!(input: input, output: out, keystore: keystore)).to eq(0)
        expect(out.string).to include("first run detected")
        expect(keystore.get("X_CLIENT_ID")).to eq("abc")
      ensure
        old_test_env ? ENV["XBOOKMARK_TEST"] = old_test_env : ENV.delete("XBOOKMARK_TEST")
      end
    end

    it "treats a complete env file as first-run configured" do
      Dir.mktmpdir do |dir|
        env_path = File.join(dir, ".env")
        File.write(env_path, "X_CLIENT_ID=abc\nX_USER_ID=42\n")
        allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
        allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

        expect(described_class.first_run_configured?(keystore: keystore)).to be(true)
      end
    end

    it "does not treat an incomplete env file as configured" do
      Dir.mktmpdir do |dir|
        env_path = File.join(dir, ".env")
        File.write(env_path, "X_CLIENT_ID=abc\n")
        allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
        allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

        expect(described_class.env_file_configured?).to be(false)
      end
    end

    it "returns false when env file loading raises" do
      allow(Xbookmark::Config).to receive(:load_env_files!).and_raise(StandardError, "bad env")

      expect(described_class.env_file_configured?).to be(false)
    end
  end
end
