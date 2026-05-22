# frozen_string_literal: true

require "yaml"

RSpec.describe "release workflow" do
  let(:workflow_path) { File.expand_path("../.github/workflows/release.yml", __dir__) }
  let(:workflow) { File.read(workflow_path) }
  let(:parsed) { YAML.load_file(workflow_path) }

  it "uses a public prerelease for URL-based smoke tests instead of a draft" do
    expect(workflow).to include("--prerelease")
    expect(workflow).not_to include("--draft")
  end

  it "keeps smoke gates strict" do
    expect(workflow).not_to include("continue-on-error: true")
    expect(workflow).not_to include("xbookmark doctor || true")
  end

  it "publishes the AUR install hook with the PKGBUILD" do
    expect(workflow).to include("cp packaging/aur/xbookmark.install /home/build/xbookmark.install")
    expect(workflow).to include("assets: packaging/aur/xbookmark.install")
  end

  it "gates promote-latest behind every smoke job and gates tap/aur publishes on promote-latest" do
    jobs = parsed.fetch("jobs")
    expect(jobs.fetch("promote-latest").fetch("needs"))
      .to match_array(%w[smoke-curl smoke-brew smoke-aur smoke-deb])
    expect(Array(jobs.fetch("update-tap").fetch("needs"))).to include("promote-latest")
    expect(Array(jobs.fetch("update-aur").fetch("needs"))).to include("promote-latest")
  end
end
