# frozen_string_literal: true

require "test_helper"

require "xbookmark/sync/pipeline"
require "xbookmark/state/store"
require "xbookmark/x/bookmark"

describe Xbookmark::Sync::Pipeline do
  def config_for(vault)
    Struct::XbookmarkConfig.new(
      vault_path: vault,
      state_db_path: ":memory:",
      logs_dir: File.join(vault, "logs"),
      scratch_dir: File.join(vault, ".xbookmark", "scratch"),
      x_client_id: "c",
      x_client_secret: nil,
      x_redirect_uri: "x",
      x_user_id: "42",
      x_access_token: "t",
      x_refresh_token: nil,
      x_token_expires_at: nil,
      codex_bin: "codex",
      whisper_bin: nil,
      whisper_model: "base.en",
      qmd_bin: "qmd",
      daily_sync_time: "06:00",
      min_run_interval_hours: 20.0,
      aux_summaries: false,
      env_file: nil,
      verbose: false
    )
  end

  def bookmark(media: [])
    Xbookmark::X::Bookmark.new(
      tweet_id: "1001",
      author_handle: "alice",
      author_name: "Alice",
      author_id: "u1",
      text: "tweet text",
      media: media,
      urls: [],
      bookmarked_at: "2026-01-01T00:00:00Z",
      created_at: "2026-01-01T00:00:00Z",
      conversation_id: "1001"
    )
  end

  def bookmark_with(id:, conversation: id, text: "tweet text")
    bm = bookmark
    bm.tweet_id = id
    bm.conversation_id = conversation
    bm.text = text
    bm
  end

  def enrichment
    Xbookmark::Enrich::EnrichmentResult.new(
      summary: "summary",
      tags: ["tag"],
      concepts: [{ "label" => "topic", "kind" => "idea" }],
      links: [],
      image_captions: {},
      image_ocr: {},
      partial: false,
      link_blobs: []
    )
  end

  it "moves downloaded media, transcribes eligible videos, skips short clips, and writes aux pages" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      media = [
        { path: File.join(config.scratch_dir, "1001", "media", "photo.jpg"), kind: "photo" },
        { path: File.join(config.scratch_dir, "1001", "media", "long.mp4"), kind: "video", duration_ms: 5000 },
        { path: File.join(config.scratch_dir, "1001", "media", "short.mp4"), kind: "video", duration_ms: 500 }
      ]
      downloader = mock("downloader")
      downloader.stubs(:download).with do |_bookmark_media, dest|
        FileUtils.mkdir_p(dest)
        media.each { |record| File.write(record[:path], "bytes") }
        true
      end.returns(media)
      whisper = mock("whisper")
      whisper.expects(:transcribe).with(media[1][:path], duration_ms: 5000).returns("spoken words")
      orch = Class.new do
        attr_reader :existing_slugs

        def initialize(result)
          @result = result
        end

        def existing_slugs=(value)
          @existing_slugs = value
        end

        def enrich(_bookmark, transcripts:, image_paths:)
          @transcripts = transcripts
          @image_paths = image_paths
          @result
        end

        def summarize_topic(slug:, snippets:)
          nil
        end
      end.new(enrichment)
      renderer = Xbookmark::Render::BookmarkRenderer.new(vault_path: vault)
      pipeline = described_class.new(config: config, store: store, orchestrator: orch,
                                     renderer: renderer, downloader: downloader, whisper: whisper)

      outcome = pipeline.process(bookmark(media: [mock("media")]))

      assert_equal :done, outcome.status
      assert outcome.markdown_path.end_with?("bookmarks/2026/01/01/alice-summary-1001.md")
      assert File.exist?(File.join(vault, "media", "1001", "photo.jpg"))
      refute File.exist?(File.join(config.scratch_dir, "1001"))
      assert_equal [], orch.existing_slugs
      assert_includes File.read(outcome.markdown_path), "## Transcript"
      assert File.exist?(File.join(vault, "authors", "alice.md"))
      assert File.exist?(File.join(vault, "concepts", "topic.md"))
      refute File.exist?(File.join(vault, "threads", "1001.md"))
    end
  end

  it "reuses a persisted readable path so a re-sync never recreates the numeric file" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      readable = "bookmarks/2026/01/01/alice-summary-1001.md"
      store.upsert_pending(tweet_id: "1001", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
      store.record_success(tweet_id: "1001", markdown_path: readable, digest: "old")
      orch = stub(enrich: enrichment)
      orch.stubs(:existing_slugs=)
      orch.stubs(:concept_registry=)
      pipeline = described_class.new(
        config: config,
        store: store,
        orchestrator: orch,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: [])
      )

      outcome = pipeline.process(bookmark)

      assert_equal File.join(vault, readable), outcome.markdown_path
      refute File.exist?(File.join(vault, "bookmarks", "2026", "01", "01", "1001.md"))
    end
  end

  it "does not create a concept page for the bookmark author handle" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      result = Xbookmark::Enrich::EnrichmentResult.new(
        summary: "geiger summary",
        tags: ["markets"],
        concepts: [{ "label" => "Geiger Capital", "kind" => "entity" }, { "label" => "oil", "kind" => "topic" }],
        links: [],
        image_captions: {},
        image_ocr: {},
        partial: false,
        link_blobs: []
      )
      orch = stub(enrich: result)
      orch.stubs(:existing_slugs=)
      orch.stubs(:concept_registry=)
      source = bookmark
      source.author_handle = "Geiger_Capital"
      source.author_name = "Geiger Capital"
      pipeline = described_class.new(
        config: config,
        store: store,
        orchestrator: orch,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: [])
      )

      outcome = pipeline.process(source)

      assert_equal :done, outcome.status
      markdown = File.read(outcome.markdown_path)
      assert_includes markdown, "[[authors/geiger_capital|@Geiger_Capital]]"
      assert_includes markdown, "[[concepts/oil|Oil]]"
      refute_includes markdown, "concepts/geiger-capital"
      assert File.exist?(File.join(vault, "authors", "geiger_capital.md"))
      assert File.exist?(File.join(vault, "concepts", "oil.md"))
      refute File.exist?(File.join(vault, "concepts", "geiger-capital.md"))
      assert_nil store.find_concept("geiger-capital")
    end
  end

  it "writes a readable thread page when local state proves a real thread" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      store.upsert_pending(
        tweet_id: "1002",
        author_handle: "alice",
        bookmarked_at: "2026-01-01T00:00:00Z",
        payload: { "data" => [{ "id" => "1002", "conversation_id" => "thread-1" }], "includes" => {}, "meta" => {} }
      )
      threaded = bookmark
      threaded.conversation_id = "thread-1"
      orch = stub(enrich: enrichment)
      orch.stubs(:existing_slugs=)
      orch.stubs(:concept_registry=)
      pipeline = described_class.new(
        config: config,
        store: store,
        orchestrator: orch,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: [])
      )

      outcome = pipeline.process(threaded)

      assert_equal :done, outcome.status
      assert File.exist?(File.join(vault, "threads", "thread-tweet-text-thread-1.md"))
      assert_includes File.read(outcome.markdown_path), "[[threads/thread-tweet-text-thread-1|Thread: tweet text]]"
    end
  end

  it "defers concept index writes until run finalization when requested" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      orch = stub(enrich: enrichment)
      orch.stubs(:existing_slugs=)
      orch.stubs(:concept_registry=)
      pipeline = described_class.new(
        config: config,
        store: store,
        orchestrator: orch,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: []),
        defer_concept_index: true
      )
      pipeline.prepare_run!

      outcome = pipeline.process(bookmark)

      assert_equal :done, outcome.status
      refute File.exist?(File.join(vault, "concepts", "index.md"))
      pipeline.finalize_run!
      assert File.exist?(File.join(vault, "concepts", "index.md"))
    end
  end

  it "graduates recurring compound concepts using per-run recurrence counts" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      orch = Class.new do
        attr_writer :existing_slugs, :concept_registry

        def enrich(_bookmark, transcripts:, image_paths:)
          Xbookmark::Enrich::EnrichmentResult.new(
            summary: "summary",
            tags: ["tag"],
            concepts: [{ "label" => "venezuelan-economy", "kind" => "subtopic" }],
            links: [],
            image_captions: {},
            image_ocr: {},
            partial: false,
            link_blobs: []
          )
        end
      end.new
      pipeline = described_class.new(
        config: config,
        store: store,
        orchestrator: orch,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: []),
        defer_concept_index: true
      )
      pipeline.prepare_run!

      3.times do |i|
        pipeline.process(bookmark_with(id: "100#{i}", text: "venezuela economy #{i}"))
      end

      assert File.exist?(File.join(vault, "concepts", "venezuela-economy.md"))
      assert_includes File.read(File.join(vault, "concepts", "venezuela-economy.md")), "broader:"
    end
  end

  it "counts existing registry evidence and plain string candidates for recurrence" do
    Dir.mktmpdir do |vault|
      pipeline = described_class.new(
        config: config_for(vault),
        store: Xbookmark::State::Store.new(":memory:"),
        orchestrator: stub,
        renderer: Xbookmark::Render::BookmarkRenderer.new(vault_path: vault),
        downloader: stub(download: [])
      )
      registry = Xbookmark::Taxonomy::Registry.new([
        Xbookmark::Taxonomy::Concept.new(slug: "existing", evidence_count: 2)
      ])

      counts = pipeline.send(:recurrence_counts_for, ["plain-topic"], registry: registry)

      assert_equal 2, counts["existing"]
      assert_equal 1, counts["plain-topic"]
    end
  end

  it "cleans scratch and classifies transient, permanent, and unexpected failures" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      renderer = Xbookmark::Render::BookmarkRenderer.new(vault_path: vault)

      failing_downloader = mock("failing downloader")
      failing_downloader.stubs(:download).raises(Xbookmark::MediaError, "network")
      transient = described_class.new(
        config: config,
        store: store,
        orchestrator: stub(enrich: enrichment),
        renderer: renderer,
        downloader: failing_downloader
      )
      assert_equal :needs_retry, transient.process(bookmark(media: [mock("media")])).status

      permanent_orch = mock("permanent orchestrator")
      permanent_orch.stubs(:enrich).raises(Xbookmark::PermanentError, "bad shape")
      permanent = described_class.new(config: config, store: store, orchestrator: permanent_orch,
                                      renderer: renderer, downloader: stub(download: []))
      assert_equal :permanent_error, permanent.process(bookmark).status

      crashing_renderer = mock("renderer")
      crashing_renderer.stubs(:render).raises(NoMethodError, "bug")
      crash = described_class.new(config: config, store: store, orchestrator: stub(enrich: enrichment),
                                  renderer: crashing_renderer, downloader: stub(download: []))
      err = capture_stderr { @outcome = crash.process(bookmark) }
      assert_match(/pipeline crashed for tweet 1001: NoMethodError/, err)
      assert_equal :permanent_error, @outcome.status
    end
  end
end
