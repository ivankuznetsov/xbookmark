# frozen_string_literal: true

require "stringio"
require "xbookmark/cli"
require "xbookmark/system/runtime"
require "xbookmark/system/package_manager"

RSpec.describe Xbookmark::CLI::Doctor do
  before do
    ENV["X_CLIENT_ID"] = "abc"
    ENV["X_USER_ID"]   = "42"
  end

  def run_doctor(opts = {})
    out = StringIO.new
    doctor = described_class.new([], opts.merge(output: out, input: StringIO.new))
    doctor.execute
    out.string
  end

  it "prints platform / ruby / keystore lines" do
    out = run_doctor
    expect(out).to match(/platform: /)
    expect(out).to match(/^ruby: /)
    expect(out).to match(/^keystore: /)
  end

  it "reports system Ruby when not running under tebako" do
    allow(Xbookmark::System::Runtime).to receive(:bundled?).and_return(false)
    out = run_doctor
    expect(out).to match(/^ruby: system \(ruby \d+\.\d+/)
  end

  it "reports bundled Tebako runtime when Runtime.bundled? is true" do
    allow(Xbookmark::System::Runtime).to receive(:bundled?).and_return(true)
    out = run_doctor
    expect(out).to match(/^ruby: bundled \(tebako/)
  end

  it "lists each missing tool with an install command for the host package manager" do
    allow(Xbookmark::System::PackageManager).to receive(:detect).and_return(:pacman)
    allow_any_instance_of(described_class).to receive(:which).and_return(nil)
    allow(Xbookmark::Transcribe::Whisper).to receive(:detect).and_return(nil)

    out = run_doctor
    expect(out).to match(/Missing tools: .*ffmpeg/)
    expect(out).to match(/ffmpeg: sudo pacman -S --needed ffmpeg/)
  end

  it "skips the fix-up section when no tools are missing" do
    allow_any_instance_of(described_class).to receive(:which).and_return("/usr/bin/fake")
    allow(Xbookmark::Transcribe::Whisper).to receive(:detect).and_return("/usr/bin/whisper")
    out = run_doctor
    expect(out).not_to match(/Missing tools:/)
  end
end

RSpec.describe Xbookmark::System::Runtime do
  it "reports :system in a normal MRI test environment" do
    expect(described_class.kind).to eq(:system)
  end

  it "describe includes the ruby version" do
    expect(described_class.describe).to include(RUBY_VERSION)
  end
end

RSpec.describe Xbookmark::System::PackageManager do
  it "returns :brew on macOS when brew is on PATH" do
    stub_platform_macos
    allow(described_class).to receive(:which).with("brew").and_return("/opt/homebrew/bin/brew")
    expect(described_class.detect).to eq(:brew)
  end

  it "returns :pacman when pacman is on PATH" do
    stub_platform_linux
    allow(described_class).to receive(:which).with("brew").and_return(nil)
    allow(described_class).to receive(:which).with("pacman").and_return("/usr/bin/pacman")
    expect(described_class.detect).to eq(:pacman)
  end

  it "renders the correct install command per manager" do
    expect(described_class.install_command("ffmpeg", manager: :brew)).to eq(["brew", "install", "ffmpeg"])
    expect(described_class.install_command("ffmpeg", manager: :pacman)).to eq(["sudo", "pacman", "-S", "--needed", "ffmpeg"])
    expect(described_class.install_command("ffmpeg", manager: :apt)).to eq(["sudo", "apt-get", "install", "-y", "ffmpeg"])
  end

  it "returns nil for tools we cannot install via the host package manager" do
    expect(described_class.install_command("qmd", manager: :pacman)).to be_nil
    expect(described_class.install_command("codex", manager: :brew)).to be_nil
  end
end
