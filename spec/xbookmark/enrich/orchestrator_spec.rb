# frozen_string_literal: true

require "xbookmark/enrich/orchestrator"
require "xbookmark/x/bookmark"

RSpec.describe Xbookmark::Enrich::Orchestrator do
  let(:bookmark) do
    Xbookmark::X::Bookmark.new(
      tweet_id: "1",
      author_handle: "alice",
      author_name: "Alice",
      author_id: "u1",
      text: "ozempic dose data",
      media: [],
      urls: [{ url: "https://t.co/x", expanded_url: "https://example.com/a", display_url: "example.com/a" }],
      bookmarked_at: "2026-01-01T00:00:00Z",
      created_at: "2026-01-01T00:00:00Z",
      conversation_id: "1"
    )
  end

  let(:link_fetcher) do
    instance_double(Xbookmark::Enrich::LinkFetcher).tap do |lf|
      allow(lf).to receive(:fetch).with(anything).and_return(
        { url: "https://example.com/a", final_url: "https://example.com/a",
          title: "Article", byline: nil, text: "body of article",
          fetched_at: "2026-01-01T00:00:00Z" }
      )
    end
  end

  it "happy path: fetches external links directly and final returns full result" do
    fake = FakeCodex.new
    fake.push({
      "summary" => "Talks about ozempic dosing.",
      "tags" => ["health"],
      "topics" => ["ozempic"],
      "entities" => ["novo-nordisk"],
      "links" => [{ "url" => "https://example.com/a", "title" => "Article", "summary" => "ok" }],
      "transcript_summaries" => { "video.mp4" => "A short transcript summary." },
      "formatted_transcripts" => { "video.mp4" => "**Speaker 1:** Hello." }
    })

    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake)
    orch = described_class.new(codex: codex, link_fetcher: link_fetcher)
    result = orch.enrich(bookmark, transcripts: { "video.mp4" => "hello" })
    expect(result.summary).to eq("Talks about ozempic dosing.")
    expect(result.tags).to eq(["health"])
    expect(result.topics).to eq(["ozempic"])
    expect(result.entities).to eq(["novo-nordisk"])
    expect(result.transcript_summaries).to eq("video.mp4" => "A short transcript summary.")
    expect(result.formatted_transcripts).to eq("video.mp4" => "**Speaker 1:** Hello.")
    expect(result.partial?).to be(false)
    # Fetched link blobs are returned so the renderer can build the
    # "Linked Articles" section without re-fetching.
    expect(result.link_blobs.size).to eq(1)
    expect(result.link_blobs.first[:url]).to eq("https://example.com/a")
    expect(fake.calls.size).to eq(1)
  end

  it "marks result partial when retry still has empty required fields" do
    fake = FakeCodex.new
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["t"], "entities" => [] })
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["t"], "entities" => [] })

    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake)
    orch = described_class.new(codex: codex, link_fetcher: link_fetcher)
    result = orch.enrich(bookmark)
    expect(result.partial?).to be(true)
  end

  it "successful retry overwrites partial result" do
    fake = FakeCodex.new
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["t"], "entities" => [] })
    fake.push({ "summary" => "x", "tags" => ["a"], "topics" => ["t"], "entities" => ["e"] })

    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake)
    orch = described_class.new(codex: codex, link_fetcher: link_fetcher)
    result = orch.enrich(bookmark)
    expect(result.partial?).to be(false)
    expect(result.tags).to eq(["a"])
    expect(result.entities).to eq(["e"])
  end

  it "does not fetch X media/status URLs as article context" do
    bookmark.urls = [{ url: "https://t.co/v", expanded_url: "https://x.com/alice/status/1/video/1" }]
    fake = FakeCodex.new.push({
      "summary" => "x",
      "tags" => ["t"],
      "topics" => ["topic"],
      "entities" => ["entity"]
    })

    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake)
    orch = described_class.new(codex: codex, link_fetcher: link_fetcher)
    result = orch.enrich(bookmark)

    expect(result.link_blobs).to be_empty
    expect(link_fetcher).not_to have_received(:fetch)
  end

  it "fetches at most three unique external article URLs from string and hash inputs" do
    bookmark.urls = [
      "https://example.com/one",
      { "expanded_url" => "https://example.com/two" },
      { expanded_url: "https://example.com/three" },
      { url: "https://example.com/four" },
      { expanded_url: "not a url" },
      { expanded_url: "https://t.co/skip" },
      { expanded_url: "https://example.com/one" }
    ]
    fake = FakeCodex.new.push({
      "summary" => "x",
      "tags" => ["t"],
      "topics" => ["topic"],
      "entities" => ["entity"]
    })
    fetched = []
    allow(link_fetcher).to receive(:fetch) do |url|
      fetched << url
      { url: url, final_url: url, title: url, byline: nil, text: "body", fetched_at: "now" }
    end

    described_class.new(codex: Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake), link_fetcher: link_fetcher)
      .enrich(bookmark)

    expect(fetched).to eq(%w[
      https://example.com/one
      https://example.com/two
      https://example.com/three
    ])
  end

  it "falls back to the first partial result when retry raises" do
    fake = FakeCodex.new
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["topic"], "entities" => [] })
    fake.push(Xbookmark::PermanentError.new("bad retry"))

    result = described_class.new(codex: Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake), link_fetcher: link_fetcher)
      .enrich(bookmark)

    expect(result).to be_partial
    expect(result.tags).to eq([])
    expect(result.entities).to eq([])
  end

  it "includes quoted tweet text in retry prompts" do
    bookmark.quoted_tweet = { "text" => "quoted context" }
    fake = FakeCodex.new
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["topic"], "entities" => [] })
    fake.push({ "summary" => "x", "tags" => ["tag"], "topics" => ["topic"], "entities" => ["entity"] })

    described_class.new(codex: Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake), link_fetcher: link_fetcher)
      .enrich(bookmark)

    expect(fake.calls.last.last).to include("quoted context")
  end

  it "includes transcript snippets in retry prompts" do
    fake = FakeCodex.new
    fake.push({ "summary" => "x", "tags" => [], "topics" => ["topic"], "entities" => [] })
    fake.push({ "summary" => "x", "tags" => ["tag"], "topics" => ["topic"], "entities" => ["entity"] })

    described_class.new(codex: Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake), link_fetcher: link_fetcher)
      .enrich(bookmark, transcripts: { "video.mp4" => "spoken words" })

    expect(fake.calls.last.last).to include("[video.mp4]\nspoken words")
  end

  it "summarizes aux pages through codex templates" do
    fake = FakeCodex.new
    fake.push({ "summary" => "Topic summary" })
    fake.push({ "summary" => "Author summary" })
    orch = described_class.new(codex: Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake), link_fetcher: link_fetcher)

    expect(orch.summarize_topic(slug: "ozempic", snippets: %w[a b])).to eq("Topic summary")
    expect(orch.summarize_author(handle: "alice", snippets: ["first"])).to eq("Author summary")
    expect(fake.calls.first.last).to include("ozempic")
    expect(fake.calls.last.last).to include("alice")
  end

  it "runs the vision prompt with image timeout when asked directly" do
    fake = FakeCodex.new.push({ "captions" => { "a.jpg" => "cap" }, "ocr" => {} })
    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake)
    orch = described_class.new(codex: codex, link_fetcher: link_fetcher)

    result = orch.send(:vision_call, ["/tmp/a.jpg"])

    expect(result["captions"]).to eq("a.jpg" => "cap")
    expect(fake.calls.first).to include("--image", "/tmp/a.jpg")
  end
end
