# frozen_string_literal: true

RSpec.describe "README setup contract" do
  let(:readme) { File.read(File.expand_path("../README.md", __dir__)) }

  it "points new setups at the implemented scheduler command" do
    expect(readme).to include("bin/xbookmark install")
    expect(readme).not_to include("bin/xbookmark schedule")
    expect(readme).not_to include("Ask me whether to install")
  end

  it "does not document deferred commands or config flags as available" do
    deferred_surface = [
      "bin/xbookmark enrich",
      "auth refresh",
      "auth logout",
      "XBOOKMARK_CONFIG",
      "--config PATH",
      "--since YYYY-MM-DD",
      "[--type lex|vec|hyde]",
      "[--json]",
      "minitest"
    ]

    deferred_surface.each do |snippet|
      expect(readme).not_to include(snippet)
    end
  end

  it "describes the runtime bookmark wiki separately from the project wiki" do
    expect(readme).to include("XBOOKMARK_WIKI_PATH")
    expect(readme).to include("separate from this repository's `wiki/` project LLM wiki")
  end
end
