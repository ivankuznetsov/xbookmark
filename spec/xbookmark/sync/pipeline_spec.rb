# frozen_string_literal: true

require "xbookmark/sync/pipeline"
require "xbookmark/state/store"
require "xbookmark/x/bookmark"

RSpec.describe Xbookmark::Sync::Pipeline do
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

  def enrichment
    Xbookmark::Enrich::EnrichmentResult.new(
      summary: "summary",
      tags: ["tag"],
      topics: ["topic"],
      entities: ["entity"],
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
      downloader = double(:downloader)
      allow(downloader).to receive(:download) do |_bookmark_media, dest|
        FileUtils.mkdir_p(dest)
        media.each { |record| File.write(record[:path], "bytes") }
        media
      end
      whisper = double(:whisper)
      allow(whisper).to receive(:transcribe).and_return("spoken words")
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

      outcome = pipeline.process(bookmark(media: [double(:media)]))

      expect(outcome.status).to eq(:done)
      expect(outcome.markdown_path).to end_with("bookmarks/2026/01/01/1001.md")
      expect(File.exist?(File.join(vault, "media", "1001", "photo.jpg"))).to be(true)
      expect(File.exist?(File.join(config.scratch_dir, "1001"))).to be(false)
      expect(whisper).to have_received(:transcribe).once.with(media[1][:path], duration_ms: 5000)
      expect(orch.existing_slugs).to eq([])
      expect(File.read(outcome.markdown_path)).to include("## Transcript")
      expect(File.exist?(File.join(vault, "authors", "alice.md"))).to be(true)
      expect(File.exist?(File.join(vault, "threads", "1001.md"))).to be(true)
    end
  end

  it "cleans scratch and classifies transient, permanent, and unexpected failures" do
    Dir.mktmpdir do |vault|
      config = config_for(vault)
      store = Xbookmark::State::Store.new(":memory:")
      renderer = Xbookmark::Render::BookmarkRenderer.new(vault_path: vault)

      failing_downloader = double(:downloader)
      allow(failing_downloader).to receive(:download).and_raise(Xbookmark::MediaError, "network")
      transient = described_class.new(
        config: config,
        store: store,
        orchestrator: double(:orch, enrich: enrichment),
        renderer: renderer,
        downloader: failing_downloader
      )
      expect(transient.process(bookmark(media: [double(:media)])).status).to eq(:needs_retry)

      permanent_orch = double(:orch)
      allow(permanent_orch).to receive(:enrich).and_raise(Xbookmark::PermanentError, "bad shape")
      permanent = described_class.new(config: config, store: store, orchestrator: permanent_orch,
                                      renderer: renderer, downloader: double(:downloader, download: []))
      expect(permanent.process(bookmark).status).to eq(:permanent_error)

      crashing_renderer = double(:renderer)
      allow(crashing_renderer).to receive(:render).and_raise(NoMethodError, "bug")
      crash = described_class.new(config: config, store: store, orchestrator: double(:orch, enrich: enrichment),
                                  renderer: crashing_renderer, downloader: double(:downloader, download: []))
      expect { @outcome = crash.process(bookmark) }
        .to output(/pipeline crashed for tweet 1001: NoMethodError/).to_stderr
      expect(@outcome.status).to eq(:permanent_error)
    end
  end
end
