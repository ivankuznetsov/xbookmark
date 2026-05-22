# frozen_string_literal: true

RSpec.describe "release workflow" do
  let(:workflow) { File.read(File.expand_path("../.github/workflows/release.yml", __dir__)) }

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
end
