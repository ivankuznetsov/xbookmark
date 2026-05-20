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
    input_lines.replace(["abc", "42", "secret", "", "n"])
    run_setup
    expect(keystore.get("X_CLIENT_ID")).to eq("abc")
    expect(keystore.get("X_USER_ID")).to eq("42")
    expect(keystore.get("X_CLIENT_SECRET")).to eq("secret")
    expect(keystore.get("X_REDIRECT_URI")).to be_nil # empty input skipped
  end

  it "skips prompts for keys already set" do
    keystore.set("X_CLIENT_ID", "preset")
    keystore.set("X_USER_ID", "preset")
    input_lines.replace(["", "", "n"]) # skip optionals, decline scheduler
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

      # answers: import? yes, delete file? no, optionals empty, scheduler? no
      input_lines.replace(["y", "n", "", "", "n"])
      run_setup
      expect(keystore.get("X_CLIENT_ID")).to eq("from-env")
      expect(keystore.get("X_USER_ID")).to eq("99")
      expect(File.file?(env_path)).to be true # not deleted
    end
  end

  it "deletes legacy .env after a successful import when user agrees" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=from-env\nX_USER_ID=99\n")
      allow(Xbookmark::Paths).to receive(:project_env_path).and_return(env_path)
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return("/nonexistent")

      input_lines.replace(["y", "y", "", "", "n"])
      run_setup
      expect(File.file?(env_path)).to be false
    end
  end

  it "calls Scheduler::Installer when the user confirms" do
    input_lines.replace(["abc", "42", "", "", "y"])
    expect(scheduler).to receive(:install)
    run_setup
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
  end
end
