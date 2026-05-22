# frozen_string_literal: true

require "xbookmark/render/bookmark_renderer"
require "xbookmark/enrich/orchestrator"
require "xbookmark/x/bookmark"
require "yaml"

RSpec.describe Xbookmark::Render::BookmarkRenderer do
  let(:bookmark) do
    Xbookmark::X::Bookmark.new(
      tweet_id: "1001",
      author_handle: "alice",
      author_name: "Alice",
      author_id: "u1",
      created_at: "2026-01-01T00:00:00Z",
      bookmarked_at: "2026-01-01T00:00:00Z",
      conversation_id: "1001",
      text: "ozempic dosing data is wild",
      media: [],
      urls: [],
      quoted_tweet_id: "9999",
      quoted_tweet: { "text" => "the quoted tweet", "author_id" => "u2", "id" => "9999" }
    )
  end

  let(:enrichment) do
    Xbookmark::Enrich::EnrichmentResult.new(
      summary: "Talks about ozempic dosing.",
      tags: ["health"],
      topics: ["ozempic", "novo-nordisk"],
      entities: ["novo-nordisk"],
      links: [{ "url" => "https://example.com/a", "title" => "Article", "summary" => "ok" }],
      image_captions: {},
      image_ocr: {},
      partial: false
    )
  end

  let(:media_records) do
    [{ path: "/vault/media/1001/photo.jpg", kind: "photo", alt_text: "chart", media_key: "m1", width: 800, height: 600, original_url: "x" }]
  end

  let(:transcripts) do
    { "video.mp4" => "spoken words about ozempic" }
  end

  it "renders a markdown file with stable frontmatter and section ordering" do
    renderer = described_class.new(vault_path: "/vault")
    md = renderer.render(bookmark, enrichment, media_records: media_records, transcripts: transcripts, link_blobs: [])
    front_yaml = md.split("---\n", 3)[1]
    front = YAML.safe_load(front_yaml)
    expect(front["xbookmark_schema"]).to eq(1)
    expect(front["tweet_id"]).to eq("1001")
    expect(front["topics"]).to eq(["ozempic", "novo-nordisk"])
    expect(front["enrichment_status"]).to eq("done")
    expect(front["media"].first["path"]).to eq("media/1001/photo.jpg")

    expect(md).to include("## Author")
    expect(md).to include("[[authors/alice|@alice]]")
    expect(md).to include("[[topics/ozempic|ozempic]]")
    expect(md).to include("[[entities/novo-nordisk|novo-nordisk]]")
    expect(md).to include("![[media/1001/photo.jpg]]")
    expect(md).to include("## Transcript")
    expect(md).to include("## Quoted")
    expect(md).to include("## Source")
    expect(md).to include("https://x.com/alice/status/1001")

    # Section ordering
    idx = ->(s) { md.index(s) }
    expect(idx.call("## Author")).to be < idx.call("## Topics")
    expect(idx.call("## Topics")).to be < idx.call("## Entities")
    expect(idx.call("## Entities")).to be < idx.call("## Media")
    expect(idx.call("## Media")).to be < idx.call("## Transcript")
    expect(idx.call("## Transcript")).to be < idx.call("## Quoted")
    expect(idx.call("## Quoted")).to be < idx.call("## Source")
  end

  it "writes the markdown to <bookmark-wiki>/bookmarks/YYYY/MM/DD/<id>.md" do
    Dir.mktmpdir do |dir|
      renderer = described_class.new(vault_path: dir)
      content = renderer.render(bookmark, enrichment, media_records: [], transcripts: {})
      path = renderer.write(bookmark, content)
      expect(path).to eq(File.join(dir, "bookmarks", "2026", "01", "01", "1001.md"))
      expect(File.read(path)).to include("ozempic dosing data is wild")
    end
  end

  it "marks enrichment_status: partial when result is partial" do
    partial = Xbookmark::Enrich::EnrichmentResult.new(
      summary: nil, tags: [], topics: [], entities: [], links: [],
      image_captions: {}, image_ocr: {}, partial: true
    )
    renderer = described_class.new(vault_path: "/vault")
    md = renderer.render(bookmark, partial)
    front = YAML.safe_load(md.split("---\n", 3)[1])
    expect(front["enrichment_status"]).to eq("partial")
  end
end
