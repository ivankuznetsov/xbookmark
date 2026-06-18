# frozen_string_literal: true

require "test_helper"

require "stringio"
require "xbookmark/cli"
require "xbookmark/system/runtime"
require "xbookmark/system/package_manager"
require "xbookmark/transcribe/whisper"
require "xbookmark/browser/chromium"
require "xbookmark/browser/session"

describe Xbookmark::CLI::Doctor do
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
    assert_match(/platform: /, out)
    assert_match(/^ruby: /, out)
    assert_match(/^keystore: /, out)
  end

  it "reports system Ruby when not running under tebako" do
    Xbookmark::System::Runtime.stubs(:bundled?).returns(false)
    out = run_doctor
    assert_match(/^ruby: system \(ruby \d+\.\d+/, out)
  end

  it "reports bundled Tebako runtime when Runtime.bundled? is true" do
    Xbookmark::System::Runtime.stubs(:bundled?).returns(true)
    out = run_doctor
    assert_match(/^ruby: bundled \(tebako/, out)
  end

  it "lists each missing tool with an install command for the host package manager" do
    Xbookmark::System::PackageManager.stubs(:detect).returns(:pacman)
    Xbookmark::Paths.stubs(:which).returns(nil)
    Xbookmark::Transcribe::Whisper.stubs(:detect).returns(nil)

    out = run_doctor
    assert_match(/Missing tools: .*ffmpeg/, out)
    assert_match(/ffmpeg: sudo pacman -S --needed ffmpeg/, out)
  end

  it "prints manual install guidance when no package manager is detected" do
    Xbookmark::System::PackageManager.stubs(:detect).returns(:unknown)
    Xbookmark::Paths.stubs(:which).returns(nil)
    Xbookmark::Transcribe::Whisper.stubs(:detect).returns(nil)

    out = run_doctor

    assert_includes out, "no supported package manager detected"
  end

  it "reports an unavailable keystore backend" do
    Xbookmark::Keystore.stubs(:default).raises(StandardError)

    out = run_doctor

    assert_includes out, "keystore: unavailable (StandardError)"
  end

  it "prompts before running fix commands and skips declined commands" do
    out = StringIO.new
    input = StringIO.new("yes\nno\nyes\n")
    doctor = described_class.new([], fix: true, output: out, input: input)
    Xbookmark::Paths.stubs(:which).returns(nil)
    Xbookmark::Transcribe::Whisper.stubs(:detect).returns(nil)
    Xbookmark::System::PackageManager.stubs(:detect).returns(:pacman)
    Xbookmark::System::PackageManager.stubs(:install_command).with("codex", manager: :pacman).returns(["echo", "codex"])
    Xbookmark::System::PackageManager.stubs(:install_command).with("whisper", manager: :pacman).returns(["echo", "whisper"])
    Xbookmark::System::PackageManager.stubs(:install_command).with("qmd", manager: :pacman).returns(nil)
    Xbookmark::System::PackageManager.stubs(:install_command).with("ffmpeg", manager: :pacman).returns(["echo", "ffmpeg"])

    doctor.expects(:system).with("echo", "codex").returns(true)
    doctor.expects(:system).with("echo", "ffmpeg").returns(true)

    doctor.execute

    assert_includes out.string, "qmd: install manually"
    assert_includes out.string, "skipped whisper"
  end

  it "skips the fix-up section when no tools are missing" do
    Xbookmark::Paths.stubs(:which).returns("/usr/bin/fake")
    Xbookmark::Transcribe::Whisper.stubs(:detect).returns("/usr/bin/whisper")
    out = run_doctor
    refute_match(/Missing tools:/, out)
  end

  it "reports browser source readiness: chromium, profile, session, source" do
    Xbookmark::Browser::Chromium.stubs(:detect).returns("/usr/bin/chromium")
    Xbookmark::Browser::Session.stubs(:profile_saved?).returns(true)

    out = run_doctor

    assert_match(/^source: api/, out)
    assert_match(%r{chromium: ok \(/usr/bin/chromium\)}, out)
    assert_match(/browser profile: /, out)
    assert_match(/browser session: profile saved but unverified/, out)
    assert_match(/validity is confirmed at next sync/, out)
  end

  it "does not nag about API login when the source is browser-only" do
    ENV["XBOOKMARK_SOURCE"] = "browser"
    out = run_doctor
    refute_match(/X auth: NOT logged in/, out)
    assert_match(/X auth: not required \(source=browser\)/, out)
  ensure
    ENV.delete("XBOOKMARK_SOURCE")
  end

  it "reports a missing Chromium and an unconfigured browser session" do
    Xbookmark::Browser::Chromium.stubs(:detect).returns(nil)
    Xbookmark::Browser::Session.stubs(:profile_saved?).returns(false)

    out = run_doctor

    assert_match(/chromium: NOT FOUND/, out)
    assert_match(/browser session: not set up/, out)
  end
end

describe Xbookmark::System::Runtime do
  it "reports :system in a normal MRI test environment" do
    assert_equal :system, described_class.kind
  end

  it "describe includes the ruby version" do
    assert_includes described_class.describe, RUBY_VERSION
  end
end

describe Xbookmark::System::PackageManager do
  it "returns :brew on macOS when brew is on PATH" do
    stub_platform_macos
    described_class.stubs(:which).with("brew").returns("/opt/homebrew/bin/brew")
    assert_equal :brew, described_class.detect
  end

  it "returns :pacman when pacman is on PATH" do
    stub_platform_linux
    described_class.stubs(:which).with("brew").returns(nil)
    described_class.stubs(:which).with("pacman").returns("/usr/bin/pacman")
    assert_equal :pacman, described_class.detect
  end

  it "detects apt, dnf, zypper, and unknown package managers in order" do
    stub_platform_linux
    described_class.stubs(:which).returns(nil)
    described_class.stubs(:which).with("apt-get").returns("/usr/bin/apt-get")
    assert_equal :apt, described_class.detect

    described_class.stubs(:which).returns(nil)
    described_class.stubs(:which).with("dnf").returns("/usr/bin/dnf")
    assert_equal :dnf, described_class.detect

    described_class.stubs(:which).returns(nil)
    described_class.stubs(:which).with("zypper").returns("/usr/bin/zypper")
    assert_equal :zypper, described_class.detect

    described_class.stubs(:which).returns(nil)
    assert_equal :unknown, described_class.detect
  end

  it "renders the correct install command per manager" do
    assert_equal ["brew", "install", "ffmpeg"], described_class.install_command("ffmpeg", manager: :brew)
    assert_equal ["sudo", "pacman", "-S", "--needed", "ffmpeg"], described_class.install_command("ffmpeg", manager: :pacman)
    assert_equal ["sudo", "apt-get", "install", "-y", "ffmpeg"], described_class.install_command("ffmpeg", manager: :apt)
    assert_equal ["sudo", "dnf", "install", "-y", "ffmpeg"], described_class.install_command("ffmpeg", manager: :dnf)
    assert_equal ["sudo", "zypper", "install", "-y", "ffmpeg"], described_class.install_command("ffmpeg", manager: :zypper)
    assert_nil described_class.install_command("ffmpeg", manager: :unknown)
  end

  it "returns nil for tools we cannot install via the host package manager" do
    assert_nil described_class.install_command("qmd", manager: :pacman)
    assert_nil described_class.install_command("codex", manager: :brew)
    assert_nil described_class.install_command("missing", manager: :brew)
  end
end
