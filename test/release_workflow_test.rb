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

  it "publishes the AUR install hook with the PKGBUILD" do
    assert_includes workflow, "cp packaging/aur/xbookmark.install /home/build/xbookmark.install"
    assert_includes workflow, "assets: packaging/aur/xbookmark.install"
  end

  it "gates promote-latest behind every smoke job and gates tap/aur publishes on promote-latest" do
    jobs = parsed.fetch("jobs")
    assert_equal %w[smoke-aur smoke-brew smoke-curl smoke-deb],
                 jobs.fetch("promote-latest").fetch("needs").sort
    assert_includes Array(jobs.fetch("update-tap").fetch("needs")), "promote-latest"
    assert_includes Array(jobs.fetch("update-aur").fetch("needs")), "promote-latest"
  end
end
