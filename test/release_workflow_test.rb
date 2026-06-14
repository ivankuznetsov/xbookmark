# frozen_string_literal: true

require "test_helper"

require "yaml"

describe "release workflow" do
  let(:workflow_path) { File.expand_path("../.github/workflows/release.yml", __dir__) }
  let(:workflow) { File.read(workflow_path) }
  let(:parsed) { YAML.load_file(workflow_path) }

  it "uses a public prerelease for URL-based smoke tests instead of a draft" do
    assert_includes workflow, "--prerelease"
    refute_includes workflow, "--draft"
  end

  it "keeps smoke gates strict" do
    refute_includes workflow, "continue-on-error: true"
    refute_includes workflow, "xbookmark doctor || true"
  end

  it "installs Tebako from the gem on macOS because Homebrew has no formula" do
    refute_includes workflow, "brew install tebako"
    assert_includes workflow, "gem install tebako --no-document"
  end

  it "uses the gem executable name as the Tebako entry point" do
    refute_includes workflow, "--entry-point=bin/xbookmark"
    assert_equal 2, workflow.scan("--entry-point=xbookmark").size
  end

  it "smoke-tests Homebrew through a local tap" do
    assert_includes workflow, "brew tap-new local/xbookmark-test"
    assert_includes workflow, "brew install local/xbookmark-test/xbookmark"
    refute_includes workflow, "brew install ./xbookmark.rb"
  end

  it "publishes the AUR install hook with the PKGBUILD" do
    assert_includes workflow, "cp packaging/aur/xbookmark.install /home/build/xbookmark.install"
    assert_includes workflow, "assets: packaging/aur/xbookmark.install"
  end

  it "skips optional package publishers when their deploy secrets are absent" do
    assert_includes workflow, "Skipping Homebrew tap publish; HOMEBREW_TAP_DEPLOY_KEY is not configured."
    assert_includes workflow, "Skipping AUR publish; AUR_SSH_PRIVATE_KEY is not configured."
    assert_includes workflow, "if: steps.publish_config.outputs.enabled == 'true'"
  end

  it "gates promote-latest behind every smoke job and gates tap/aur publishes on promote-latest" do
    jobs = parsed.fetch("jobs")
    assert_equal %w[smoke-aur smoke-brew smoke-curl smoke-deb],
                 jobs.fetch("promote-latest").fetch("needs").sort
    assert_includes Array(jobs.fetch("update-tap").fetch("needs")), "promote-latest"
    assert_includes Array(jobs.fetch("update-aur").fetch("needs")), "promote-latest"
  end
end
