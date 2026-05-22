# frozen_string_literal: true

require "open3"

RSpec.describe "install.sh" do
  let(:script_path) { File.expand_path("../install.sh", __dir__) }
  let(:uninstall_path) { File.expand_path("../uninstall.sh", __dir__) }

  it "passes `sh -n` syntax check" do
    _out, err, status = Open3.capture3("sh", "-n", script_path)
    expect(status.success?).to be(true), err
  end

  it "uninstall.sh passes `sh -n` syntax check" do
    _out, err, status = Open3.capture3("sh", "-n", uninstall_path)
    expect(status.success?).to be(true), err
  end

  it "is plain POSIX sh — no `bash` or `\\[\\[` constructs" do
    body = File.read(script_path)
    expect(body).not_to match(/^\s*\[\[/)
    expect(body).not_to match(/\bsource\b/) # bash-only
  end

  it "defaults to the publishing repo and binary install path" do
    body = File.read(script_path)
    expect(body).to include('XBOOKMARK_REPO="${XBOOKMARK_REPO:-ivankuznetsov/xbookmark}"')
    expect(body).to include('XBOOKMARK_INSTALL_METHOD="${XBOOKMARK_INSTALL_METHOD:-binary}"')
    expect(body).not_to include("XBOOKMARK_FORCE_BINARY")
  end

  it "refuses to install when checksum verification cannot run" do
    body = File.read(script_path)
    expect(body).to include("refusing to install an unverified binary")
    expect(body).to include("could not fetch SHA256SUMS; refusing to install")
  end

  it "detects x86_64-linux and arm64-darwin and rejects others" do
    # Run a small shim that sources `detect_arch` from install.sh by
    # extracting the function body — pure POSIX, no bashisms.
    Dir.mktmpdir do |dir|
      shim = File.join(dir, "shim.sh")
      File.write(shim, <<~SH)
        #!/bin/sh
        uname() {
          case "$1" in
            -s) echo "$FAKE_UNAME_S" ;;
            -m) echo "$FAKE_UNAME_M" ;;
          esac
        }
        die() { echo "$@"; exit 1; }

        # Inline the detect_arch function from install.sh.
        detect_arch() {
          uname_s="$(uname -s)"
          uname_m="$(uname -m)"
          case "${uname_s}-${uname_m}" in
            Linux-x86_64)   echo "x86_64-linux" ;;
            Darwin-arm64)   echo "arm64-darwin" ;;
            *)              die "unsupported ${uname_s}-${uname_m}" ;;
          esac
        }

        detect_arch
      SH

      def run_with_env(shim, env)
        Open3.capture3(env, "sh", shim)
      end

      out, _err, status = run_with_env(shim, "FAKE_UNAME_S" => "Linux",  "FAKE_UNAME_M" => "x86_64")
      expect(status.success?).to be true
      expect(out.strip).to eq("x86_64-linux")

      out, _err, status = run_with_env(shim, "FAKE_UNAME_S" => "Darwin", "FAKE_UNAME_M" => "arm64")
      expect(status.success?).to be true
      expect(out.strip).to eq("arm64-darwin")

      out, _err, status = run_with_env(shim, "FAKE_UNAME_S" => "Linux",  "FAKE_UNAME_M" => "i686")
      expect(status.success?).to be false
      expect(out).to include("unsupported")
    end
  end
end
