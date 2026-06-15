# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/bookmark_renderer"
require "xbookmark/enrich/orchestrator"
require "xbookmark/x/bookmark"
require "yaml"

describe Xbookmark::Render::BookmarkRenderer do
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
      concepts: [
        { "label" => "ozempic", "kind" => "entity" },
        { "label" => "novo-nordisk", "kind" => "organization" }
      ],
      links: [{ "url" => "https://example.com/a", "title" => "Article", "summary" => "ok" }],
      image_captions: {},
      image_ocr: {},
      transcript_summaries: { "video.mp4" => "A short explanation of the dosing point." },
      formatted_transcripts: {
        "video.mp4" => "**Speaker 1:** Dosing changed.\n\n**Speaker 2:** The chart explains why."
      },
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
    assert_equal 1, front["xbookmark_schema"]
    assert_equal "1001", front["tweet_id"]
    assert_equal ["ozempic", "novo-nordisk"], front["concepts"]
    assert_equal "done", front["enrichment_status"]
    assert_equal "media/1001/photo.jpg", front["media"].first["path"]
    assert_equal ["[[media/1001/photo.jpg]]"], front["media_files"]

    assert_includes md, "## Author"
    assert_includes md, "[[authors/alice|@alice]]"
    assert_includes md, "## Concepts"
    assert_includes md, "[[concepts/ozempic|ozempic]]"
    assert_includes md, "[[concepts/novo-nordisk|novo-nordisk]]"
    assert_includes md, "![[media/1001/photo.jpg]]"
    assert_includes md, "[Open photo.jpg](../../../../media/1001/photo.jpg)"
    assert_includes md, "## Transcript"
    assert_includes md, "#### Summary"
    assert_includes md, "A short explanation of the dosing point."
    assert_includes md, "**Speaker 1:** Dosing changed."
    assert_includes md, "## Quoted"
    assert_includes md, "## Source"
    assert_includes md, "https://x.com/alice/status/1001"

    # Section ordering
    idx = ->(s) { md.index(s) }
    assert_operator idx.call("## Author"), :<, idx.call("## Concepts")
    assert_operator idx.call("## Concepts"), :<, idx.call("## Media")
    assert_operator idx.call("## Media"), :<, idx.call("## Transcript")
    assert_operator idx.call("## Transcript"), :<, idx.call("## Quoted")
    assert_operator idx.call("## Quoted"), :<, idx.call("## Source")
  end

  it "writes the markdown to a readable source path with an id suffix" do
    Dir.mktmpdir do |dir|
      renderer = described_class.new(vault_path: dir)
      content = renderer.render(bookmark, enrichment, media_records: [], transcripts: {})
      path = renderer.write(bookmark, content, enrichment: enrichment)
      assert_equal File.join(dir, "bookmarks", "2026", "01", "01", "alice-talks-about-ozempic-dosing-1001.md"), path
      assert_includes File.read(path), "ozempic dosing data is wild"
    end
  end

  it "marks enrichment_status: partial when result is partial" do
    partial = Xbookmark::Enrich::EnrichmentResult.new(
      summary: nil, tags: [], concepts: [], links: [],
      image_captions: {}, image_ocr: {}, partial: true
    )
    renderer = described_class.new(vault_path: "/vault")
    md = renderer.render(bookmark, partial)
    front = YAML.safe_load(md.split("---\n", 3)[1])
    assert_equal "partial", front["enrichment_status"]
  end

  it "falls back to raw transcript text when enrichment has no formatted transcript" do
    raw = Xbookmark::Enrich::EnrichmentResult.new(
      summary: nil, tags: [], concepts: [], links: [],
      image_captions: {}, image_ocr: {}, partial: false
    )
    renderer = described_class.new(vault_path: "/vault")
    md = renderer.render(bookmark, raw, transcripts: { "video.mp4" => "raw whisper text" })

    assert_includes md, "### video.mp4"
    assert_includes md, "#### Transcript"
    assert_includes md, "raw whisper text"
  end

  it "renders string concepts and explicit thread links" do
    raw = Xbookmark::Enrich::EnrichmentResult.new(
      summary: nil, tags: [], concepts: ["venezuela"], links: [],
      image_captions: {}, image_ocr: {}, partial: false
    )
    renderer = described_class.new(vault_path: "/vault")
    md = renderer.render(bookmark, raw, thread: { target: "threads/alice-1001-thread", label: "thread alice" })

    assert_includes md, "[[concepts/venezuela|Venezuela]]"
    assert_includes md, "## Thread"
    assert_includes md, "[[threads/alice-1001-thread|thread alice]]"
  end

  it "falls back to created_at for invalid bookmarked_at and renders captions plus unavailable quotes" do
    fallback_bookmark = bookmark.dup
    fallback_bookmark.bookmarked_at = "not a date"
    fallback_bookmark.created_at = "2026-02-03T00:00:00Z"
    fallback_bookmark.quoted_tweet = nil
    enrichment.image_captions = { "photo.jpg" => "A useful chart" }
    renderer = described_class.new(vault_path: "/vault")

    assert_equal "/vault/bookmarks/2026/02/03/alice-talks-about-ozempic-dosing-1001.md",
                 renderer.markdown_path_for(fallback_bookmark, enrichment: enrichment)

    md = renderer.render(fallback_bookmark, enrichment, media_records: media_records)
    assert_includes md, "Captions:"
    assert_includes md, "- `photo.jpg`: A useful chart"
    assert_includes md, "(quoted tweet not available)"
  end

  it "keeps external media paths absolute and omits source when the tweet URL cannot be built" do
    no_source = bookmark.dup
    no_source.author_handle = nil
    no_source.tweet_id = nil
    renderer = described_class.new(vault_path: "/vault")

    md = renderer.render(no_source, enrichment, media_records: [{ path: "/elsewhere/photo.jpg", kind: "photo" }])

    assert_includes md, "![[/elsewhere/photo.jpg]]"
    refute_includes md, "## Source"
  end

  it "falls back to the stored media path when it cannot compute a note-relative link" do
    renderer = described_class.new(vault_path: "/vault")

    md = renderer.render(bookmark, enrichment, media_records: [{ path: "relative media/file (1).jpg", kind: "photo" }])

    assert_includes md, "![[relative media/file (1).jpg]]"
    assert_includes md, "[Open file (1).jpg](relative%20media/file%20%281%29.jpg)"
  end
end
