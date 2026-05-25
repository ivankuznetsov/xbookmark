# frozen_string_literal: true

require "test_helper"

require "xbookmark/sync/runner"
require "xbookmark/state/store"
require "xbookmark/qmd/searcher"
require "xbookmark/qmd/registrar"

# End-to-end-ish acceptance test for v1: 10 fixture bookmarks (image,
# video, quote-tweet, link variants) flow through the runner with a fake
# X client, fake codex, and stubbed media/whisper layers — no network.
describe "v1 acceptance" do
  let(:vault) { Dir.mktmpdir("xbookmark-wiki") }

  let(:bookmarks_payload) do
    data = []
    includes_users = []
    includes_media = []
    10.times do |i|
      day = (i % 5) + 1
      tweet_id = "20#{format("%03d", i)}"
      author = i.even? ? "alice" : "bob"
      mkey = "m#{i}"
      record = {
        "id" => tweet_id,
        "author_id" => "u_#{author}",
        "text" => i.even? ? "ozempic dosing experience #{i}" : "ai agents thoughts #{i}",
        "created_at" => "2026-01-0#{day}T00:00:00Z",
        "conversation_id" => tweet_id
      }
      if i % 4 == 1
        record["attachments"] = { "media_keys" => [mkey] }
        includes_media << { "media_key" => mkey, "type" => "photo", "url" => "https://x/img-#{i}.jpg",
                            "width" => 800, "height" => 600 }
      end
      if i % 4 == 2
        record["attachments"] = { "media_keys" => [mkey] }
        includes_media << { "media_key" => mkey, "type" => "video", "duration_ms" => 4000,
                            "variants" => [{ "bit_rate" => 832_000, "content_type" => "video/mp4",
                                             "url" => "https://x/vid-#{i}.mp4" }] }
      end
      if i == 3
        record["referenced_tweets"] = [{ "type" => "quoted", "id" => "9999" }]
      end
      if i == 5
        record["entities"] = { "urls" => [{ "url" => "https://t.co/x", "expanded_url" => "https://example.com/article", "display_url" => "example.com/article" }] }
      end
      data << record
    end

    includes_users << { "id" => "u_alice", "username" => "alice", "name" => "Alice", "profile_image_url" => "https://x/p1.jpg" }
    includes_users << { "id" => "u_bob",   "username" => "bob",   "name" => "Bob",   "profile_image_url" => "https://x/p2.jpg" }

    { "data" => data, "includes" => { "users" => includes_users, "media" => includes_media,
                                      "tweets" => [{ "id" => "9999", "text" => "the quoted tweet", "author_id" => "u_bob", "created_at" => "2025-12-30T00:00:00Z" }] },
      "meta" => { "result_count" => data.size } }
  end

  let(:fake_x_client) do
    Class.new do
      def initialize(payload); @payload = payload; end
      def bookmarks(user_id:, pagination_token: nil, max_results: 100)
        return enum_for(:bookmarks, user_id: user_id, pagination_token: pagination_token, max_results: max_results) unless block_given?
        yield @payload
      end
      def get_tweet(_id); raise NotImplementedError; end
    end.new(bookmarks_payload)
  end

  let(:fake_downloader) do
    Class.new do
      def download(media_list, dest_dir)
        FileUtils.mkdir_p(dest_dir)
        media_list.map do |m|
          if m.image?
            path = File.join(dest_dir, "img-#{m.media_key}.jpg")
            File.binwrite(path, "fake-image-bytes-#{m.media_key}")
            { path: path, kind: "photo", original_url: m.url, alt_text: nil, media_key: m.media_key, width: m.width, height: m.height, duration_ms: nil }
          elsif m.type == "video"
            path = File.join(dest_dir, "vid-#{m.media_key}.mp4")
            File.binwrite(path, "fake-video-bytes-#{m.media_key}")
            { path: path, kind: "video", original_url: nil, alt_text: nil, media_key: m.media_key, width: m.width, height: m.height, duration_ms: m.duration_ms }
          end
        end.compact
      end
    end.new
  end

  let(:fake_whisper) do
    Class.new do
      def transcribe(media_path, duration_ms: nil)
        return "" if duration_ms && duration_ms < 1500
        "transcribed audio of #{File.basename(media_path)}"
      end
    end.new
  end

  let(:fake_codex_runner) do
    # codex stub: inspect the prompt passed over stdin, then respond
    # deterministically based on which prompt template was used.
    ->(_argv, _timeout, stdin_data = "") {
      prompt = stdin_data
      response =
        if prompt.include?("Read the tweet and any media descriptions")
          { "fetch_external_links" => prompt.include?("example.com/article") ? ["https://example.com/article"] : [], "summarize_quoted_tweet" => false, "needs_image_ocr" => false }
        elsif prompt.start_with?("Look at the attached image")
          { "captions" => {}, "ocr" => {} }
        elsif prompt.include?("Summarize what the user's bookmark collection says about")
          { "summary" => "auto topic summary" }
        elsif prompt.include?("Write a one-paragraph sketch")
          { "summary" => "auto author summary" }
        else
          # final.txt — match on tweet_text section only (between "Tweet text:" and the next blank+section)
          tweet_text_section = prompt[/Tweet text:\n(.*?)(\n\n|\nAuthor:)/m, 1].to_s
          if tweet_text_section.include?("ozempic")
            { "summary" => "Talks about ozempic dosing.", "tags" => ["health"], "topics" => ["ozempic"], "entities" => ["novo-nordisk"], "links" => [] }
          else
            { "summary" => "Talks about ai agents.", "tags" => ["ai"], "topics" => ["ai-agents"], "entities" => ["openai"], "links" => [] }
          end
        end
      [JSON.generate(response), "", FakeCodex::DummyStatus.new(0)]
    }
  end

  let(:store) { Xbookmark::State::Store.new(":memory:") }

  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: vault, state_db_path: ":memory:", logs_dir: "/tmp",
      scratch_dir: File.join(vault, ".xbookmark", "scratch"),
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: "/fake/whisper", whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      env_file: nil, verbose: false
    )
  end

  it "writes 10 markdown files, aux pages, no leftover .tmp, and qmd find returns hits" do
    codex = Xbookmark::Enrich::Codex.new(bin: "codex", runner: fake_codex_runner)
    fake_link_fetcher = mock("link fetcher")
    fake_link_fetcher.stubs(:fetch).returns(
      { url: "https://example.com/article", final_url: "https://example.com/article",
        title: "Article", byline: nil, text: "article body", fetched_at: "2026-01-01T00:00:00Z" }
    )
    orchestrator = Xbookmark::Enrich::Orchestrator.new(codex: codex, link_fetcher: fake_link_fetcher)
    renderer = Xbookmark::Render::BookmarkRenderer.new(vault_path: vault)
    pipeline = Xbookmark::Sync::Pipeline.new(
      config: config, store: store, orchestrator: orchestrator, renderer: renderer,
      downloader: fake_downloader, whisper: fake_whisper
    )
    fake_registrar = Class.new do
      attr_reader :index_calls
      def initialize; @index_calls = 0; end
      def index!; @index_calls += 1; end
    end.new
    runner = Xbookmark::Sync::Runner.new(
      config: config, store: store, x_client: fake_x_client,
      orchestrator: orchestrator, renderer: renderer, pipeline: pipeline,
      registrar: fake_registrar
    )

    report = runner.run(mode: :backfill_limited, limit: 10)
    assert_equal 10, report.synced
    assert_equal 0, report.failed
    assert_equal 0, report.permanent_errors

    # 10 .md files in date-sharded folders
    md_files = Dir.glob(File.join(vault, "bookmarks", "**/*.md"))
    assert_equal 10, md_files.size

    # No leftover .tmp anywhere in the bookmark wiki
    leftovers = Dir.glob(File.join(vault, "**/*.tmp.*"))
    assert_empty leftovers

    # Aux pages exist (authors, topics, entities)
    assert File.exist?(File.join(vault, "authors", "alice.md"))
    assert File.exist?(File.join(vault, "authors", "bob.md"))
    assert File.exist?(File.join(vault, "topics", "ozempic.md"))
    assert File.exist?(File.join(vault, "topics", "ai-agents.md"))
    assert File.exist?(File.join(vault, "entities", "novo-nordisk.md"))
    assert File.exist?(File.join(vault, "entities", "openai.md"))

    # Mode advanced to test_backfilled
    assert_equal "test_backfilled", store.mode

    # qmd find: stub the runner to return one of the markdown paths
    qmd_runner = ->(_argv) {
      json = [{ "path" => md_files.first, "score" => 0.9, "snippet" => "ozempic dosing" }].to_json
      [json, "", FakeCodex::DummyStatus.new(0)]
    }
    hits = Xbookmark::Qmd::Searcher.new(config: config, runner: qmd_runner).search("ozempic")
    assert_equal md_files.first, hits.first[:path]

    # qmd index! is called after a successful sync so search results stay fresh.
    assert_equal 1, fake_registrar.index_calls
  end
end
