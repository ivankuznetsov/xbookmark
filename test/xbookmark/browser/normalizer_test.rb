# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/normalizer"
require "xbookmark/x/expansions"
require "xbookmark/media/variant_picker"

describe Xbookmark::Browser::Normalizer do
  let(:page) { fixture_json("browser", "bookmarks_page.json") }

  def envelope(payload = page)
    described_class.new(payload).envelope
  end

  def bookmarks(payload = page)
    Xbookmark::X::Expansions.new(envelope(payload)).bookmarks
  end

  it "extracts the bottom cursor as meta.next_token" do
    assert_equal "cursor-bottom-value-1", envelope["meta"]["next_token"]
  end

  it "normalizes every TimelineTweet entry and dedupes includes" do
    env = envelope
    assert_equal %w[1001 1002 1003 1004 1005], env["data"].map { |t| t["id"] }
    assert_equal %w[alice bob], env["includes"]["users"].map { |u| u["username"] }
    assert_equal %w[m1 v1 g1], env["includes"]["media"].map { |m| m["media_key"] }
    assert_equal %w[9999], env["includes"]["tweets"].map { |t| t["id"] }
  end

  it "maps author handle, name, and profile image through Expansions" do
    alice = bookmarks.find { |b| b.tweet_id == "1001" }
    assert_equal "alice", alice.author_handle
    assert_equal "Alice", alice.author_name
    assert_equal "https://x/p1.jpg", alice.author_profile_image
  end

  it "carries conversation_id and entity urls" do
    alice = bookmarks.find { |b| b.tweet_id == "1001" }
    assert_equal "1001", alice.conversation_id
    assert_equal ["https://example.com/a"], alice.urls.map { |u| u[:expanded_url] }
  end

  it "normalizes a photo into a downloadable media object" do
    photo = bookmarks.find { |b| b.tweet_id == "1001" }.media.first
    assert_equal "photo", photo.type
    assert_equal "https://x/img.jpg", photo.url
    assert_equal 800, photo.width
    assert_equal 600, photo.height
    assert_equal "a chart", photo.alt_text
  end

  it "normalizes video variants so VariantPicker selects the best mp4" do
    video = bookmarks.find { |b| b.tweet_id == "1002" }.media.first
    assert_equal "video", video.type
    assert_equal "https://x/preview.jpg", video.preview_image_url
    assert_equal 12_000, video.duration_ms
    assert_equal "https://x/hi.mp4", Xbookmark::Media::VariantPicker.best_video_url(video)
  end

  it "normalizes an animated_gif" do
    gif = bookmarks.find { |b| b.tweet_id == "1004" }.media.first
    assert_equal "animated_gif", gif.type
    assert gif.video?
  end

  it "wires a quoted tweet's id and object" do
    quote = bookmarks.find { |b| b.tweet_id == "1003" }
    assert_equal "9999", quote.quoted_tweet_id
    assert_equal "the quoted tweet", quote.quoted_tweet["text"]
  end

  it "marks a reply with replied_to and prefers longform note_tweet text" do
    reply = bookmarks.find { |b| b.tweet_id == "1005" }
    assert_equal "8888", reply.in_reply_to_tweet_id
    assert_match(/long-form reply that exceeds/, reply.text)
  end

  # ---- AC4 parity: a browser-sourced bookmark matches the API-path fixture ----

  it "produces Bookmarks structurally identical to the equivalent API-path fixture" do
    api_fixture = fixture_json("x", "bookmarks_page.json")
    api = Xbookmark::X::Expansions.new(api_fixture).bookmarks
    browser = bookmarks

    %w[1001 1002 1003].each do |id|
      a = api.find { |b| b.tweet_id == id }
      b = browser.find { |bm| bm.tweet_id == id }

      assert_equal a.url, b.url, "url parity for #{id}"
      assert_equal a.author_handle, b.author_handle, "author parity for #{id}"
      assert_equal a.text, b.text, "text parity for #{id}"
      assert_equal a.created_at, b.created_at, "created_at parity for #{id}"
      assert_equal a.media.map(&:type), b.media.map(&:type), "media kinds parity for #{id}"
      assert_equal a.media.map(&:url), b.media.map(&:url), "media url parity for #{id}"
      assert_equal a.quoted_tweet_id.to_s, b.quoted_tweet_id.to_s, "quoted id parity for #{id}"
    end

    # Quoted-tweet object resolves on both paths.
    assert_equal(
      api.find { |b| b.tweet_id == "1003" }.quoted_tweet["text"],
      browser.find { |b| b.tweet_id == "1003" }.quoted_tweet["text"]
    )

    # AC4: the video (1002) must round-trip its picked variant, preview image,
    # and duration identically. media.url is nil for video on both paths, so the
    # url-parity assertion above is vacuous for it — compare the fields that
    # actually carry the video so a regression on the browser path would fail.
    a_video = api.find { |b| b.tweet_id == "1002" }.media.first
    b_video = browser.find { |b| b.tweet_id == "1002" }.media.first
    assert_equal a_video.preview_image_url, b_video.preview_image_url, "video preview_image_url parity"
    assert_equal a_video.duration_ms, b_video.duration_ms, "video duration_ms parity"
    assert_equal Xbookmark::Media::VariantPicker.best_video_url(a_video),
                 Xbookmark::Media::VariantPicker.best_video_url(b_video), "video picked-variant parity"

    # AC4 (animated_gif + reply): the shared x/bookmarks_page.json fixture is held
    # at exactly three bookmarks (other suites assert that), so the API-shape
    # counterparts for the browser's gif (1004) and reply (1005) are built inline
    # here and run through the same cross-path equivalence as 1001-1003.
    api_extra = Xbookmark::X::Expansions.new(
      "data" => [
        { "id" => "1004", "author_id" => "u1", "text" => "gif tweet",
          "created_at" => "2026-01-04T00:00:00.000Z", "conversation_id" => "1004",
          "attachments" => { "media_keys" => ["g1"] } },
        { "id" => "1005", "author_id" => "u2",
          "text" => "a long-form reply that exceeds the classic 280 character limit and is carried in note_tweet",
          "created_at" => "2026-01-05T00:00:00.000Z", "conversation_id" => "8888",
          "referenced_tweets" => [{ "type" => "replied_to", "id" => "8888" }] }
      ],
      "includes" => { "media" => [
        { "media_key" => "g1", "type" => "animated_gif", "preview_image_url" => "https://x/gif-preview.jpg",
          "variants" => [{ "content_type" => "video/mp4", "url" => "https://x/anim.mp4" }] }
      ] },
      "meta" => {}
    ).bookmarks

    a_gif = api_extra.find { |b| b.tweet_id == "1004" }.media.first
    b_gif = browser.find { |b| b.tweet_id == "1004" }.media.first
    assert_equal a_gif.type, b_gif.type, "animated_gif media.type parity"
    assert_equal "animated_gif", b_gif.type
    assert_equal Xbookmark::Media::VariantPicker.best_video_url(a_gif),
                 Xbookmark::Media::VariantPicker.best_video_url(b_gif), "animated_gif picked-variant parity"

    a_reply = api_extra.find { |b| b.tweet_id == "1005" }
    b_reply = browser.find { |b| b.tweet_id == "1005" }
    assert_equal a_reply.in_reply_to_tweet_id, b_reply.in_reply_to_tweet_id, "reply in_reply_to_tweet_id parity"
    assert_equal "8888", b_reply.in_reply_to_tweet_id
    assert_equal a_reply.text, b_reply.text, "reply text parity"
  end

  # ---- pagination / cursor edge cases ----

  it "returns no next_token when the page has no bottom cursor" do
    page["data"]["bookmark_timeline_v2"]["timeline"]["instructions"][1]["entries"].reject! do |e|
      e.dig("content", "cursorType") == "Bottom"
    end
    refute envelope.fetch("meta").key?("next_token")
  end

  it "falls back to the legacy bookmark_timeline key" do
    timeline = page["data"]["bookmark_timeline_v2"]["timeline"]
    payload = { "data" => { "bookmark_timeline" => { "timeline" => timeline } } }
    assert_equal %w[1001 1002 1003 1004 1005], envelope(payload)["data"].map { |t| t["id"] }
  end

  it "parses a committed legacy bookmark_timeline fixture end to end" do
    payload = fixture_json("browser", "bookmarks_page_legacy.json")
    env = described_class.new(payload).envelope
    assert_equal %w[3001], env["data"].map { |t| t["id"] }
    assert_equal "cursor-legacy-bottom", env["meta"]["next_token"]
    assert_equal %w[legacyuser], env["includes"]["users"].map { |u| u["username"] }
  end

  it "returns an empty envelope for an unrecognized payload" do
    env = envelope({})
    assert_empty env["data"]
    assert_empty env["includes"]["users"]
    refute env["meta"].key?("next_token")
  end

  # ---- result-shape edge cases (inline payloads) ----

  def single_entry_envelope(result)
    payload = {
      "data" => { "bookmark_timeline_v2" => { "timeline" => { "instructions" => [
        { "type" => "TimelineAddEntries", "entries" => [
          { "content" => { "entryType" => "TimelineTimelineItem",
                           "itemContent" => { "itemType" => "TimelineTweet",
                                             "tweet_results" => { "result" => result } } } }
        ] }
      ] } } }
    }
    described_class.new(payload).envelope
  end

  it "skips non-tweet timeline items (tombstones)" do
    payload = {
      "data" => { "bookmark_timeline_v2" => { "timeline" => { "instructions" => [
        { "type" => "TimelineAddEntries", "entries" => [
          { "content" => { "entryType" => "TimelineTimelineItem",
                           "itemContent" => { "itemType" => "TimelineTombstone" } } },
          { "content" => { "entryType" => "TimelineTimelineModule" } }
        ] }
      ] } } }
    }
    assert_empty described_class.new(payload).envelope["data"]
  end

  it "reads the newer core.screen_name/name user shape and avatar fallback" do
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2001",
      "core" => { "user_results" => { "result" => {
        "rest_id" => "u9",
        "core" => { "screen_name" => "carol", "name" => "Carol" },
        "avatar" => { "image_url" => "https://x/avatar.jpg" }
      } } },
      "legacy" => { "id_str" => "2001", "full_text" => "hi", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
    }
    user = single_entry_envelope(result)["includes"]["users"].first
    assert_equal "carol", user["username"]
    assert_equal "Carol", user["name"]
    assert_equal "https://x/avatar.jpg", user["profile_image_url"]
  end

  it "unwraps TweetWithVisibilityResults and uses legacy text fallback" do
    result = {
      "__typename" => "TweetWithVisibilityResults",
      "tweet" => {
        "rest_id" => "2002",
        "legacy" => { "id_str" => "2002", "text" => "limited visibility",
                      "created_at" => "Thu Jan 01 00:00:00 +0000 2026", "user_id_str" => "u1" }
      }
    }
    env = single_entry_envelope(result)
    assert_equal "limited visibility", env["data"].first["text"]
    assert_equal "u1", env["data"].first["author_id"]
  end

  it "registers a legacy-only author when the embedded user object is absent" do
    # A restricted/withheld author can arrive with no core.user_results.result,
    # only the tweet legacy's user_id_str. Without a fallback users entry,
    # Expansions resolves the author to {} and Bookmark#url breaks — so a minimal
    # id-keyed user must still be registered (parity with author_id's fallback).
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2100",
      "legacy" => { "id_str" => "2100", "user_id_str" => "u-legacy", "full_text" => "t",
                    "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
    }
    env = single_entry_envelope(result)
    assert_equal "u-legacy", env["data"].first["author_id"]
    assert_equal %w[u-legacy], env["includes"]["users"].map { |u| u["id"] }
  end

  it "reads note_tweet entity_set urls when the text comes from a long-form note" do
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2200",
      "note_tweet" => { "note_tweet_results" => { "result" => {
        "text" => "a long-form note carrying a link",
        "entity_set" => { "urls" => [
          { "url" => "https://t.co/note", "expanded_url" => "https://example.com/note", "display_url" => "example.com/note" }
        ] }
      } } },
      "legacy" => { "id_str" => "2200", "full_text" => "truncated note text…",
                    "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
    }
    env = single_entry_envelope(result)
    tweet = env["data"].first
    assert_equal "a long-form note carrying a link", tweet["text"]
    assert_equal ["https://example.com/note"], tweet["entities"]["urls"].map { |u| u["expanded_url"] }
  end

  it "does not overflow the stack on a self-referential quoted tweet" do
    # A hostile payload where a tweet inline-quotes itself would recurse forever
    # without the depth guard — and SystemStackError (< Exception) escapes every
    # rescue StandardError at the source/runner boundary. It must degrade to a
    # bounded result instead.
    result = { "__typename" => "Tweet", "rest_id" => "3000",
               "legacy" => { "id_str" => "3000", "full_text" => "loop",
                             "created_at" => "Thu Jan 01 00:00:00 +0000 2026" } }
    result["quoted_status_result"] = { "result" => result } # self-reference
    env = single_entry_envelope(result)
    assert_equal "3000", env["data"].first["id"]
  end

  it "drops a visibility wrapper with no inner tweet" do
    result = { "__typename" => "TweetWithVisibilityResults" }
    assert_empty single_entry_envelope(result)["data"]
  end

  it "drops a tweet result with no id" do
    result = { "__typename" => "Tweet", "legacy" => {} }
    assert_empty single_entry_envelope(result)["data"]
  end

  it "drops a tweet whose author has no rest_id and skips media without a key" do
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2003",
      "core" => { "user_results" => { "result" => { "legacy" => { "screen_name" => "x" } } } },
      "legacy" => {
        "id_str" => "2003", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
        "extended_entities" => { "media" => [{ "type" => "photo", "media_url_https" => "https://x/n.jpg" }] }
      }
    }
    env = single_entry_envelope(result)
    assert_empty env["includes"]["users"]
    assert_empty env["includes"]["media"]
    assert_equal [], env["data"].first["attachments"]["media_keys"]
  end

  it "falls back to entities.media when extended_entities is absent" do
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2004",
      "legacy" => {
        "id_str" => "2004", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
        "entities" => { "media" => [{ "media_key" => "p9", "type" => "photo", "media_url_https" => "https://x/e.jpg" }] }
      }
    }
    env = single_entry_envelope(result)
    assert_equal %w[p9], env["includes"]["media"].map { |m| m["media_key"] }
  end

  it "falls back to entities.media when extended_entities.media is present but empty" do
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2005",
      "legacy" => {
        "id_str" => "2005", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
        "extended_entities" => { "media" => [] },
        "entities" => { "media" => [{ "media_key" => "p10", "type" => "photo", "media_url_https" => "https://x/e2.jpg" }] }
      }
    }
    env = single_entry_envelope(result)
    assert_equal %w[p10], env["includes"]["media"].map { |m| m["media_key"] }
    assert_equal %w[p10], env["data"].first["attachments"]["media_keys"]
  end

  it "drops the variants key for a video whose video_info carries no variants" do
    # video_variants returns nil when video_info has no `variants` key, and the
    # `.compact` in normalize_media drops the key — so VariantPicker sees no
    # candidates and returns nil rather than crashing on a missing field.
    result = {
      "__typename" => "Tweet",
      "rest_id" => "2006",
      "core" => { "user_results" => { "result" => {
        "rest_id" => "u1", "legacy" => { "screen_name" => "alice", "name" => "Alice" }
      } } },
      "legacy" => {
        "id_str" => "2006", "user_id_str" => "u1", "full_text" => "t",
        "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
        "extended_entities" => { "media" => [
          { "media_key" => "v9", "type" => "video", "media_url_https" => "https://x/thumb.jpg",
            "video_info" => { "duration_millis" => 5000 } }
        ] }
      }
    }
    env = single_entry_envelope(result)
    media = env["includes"]["media"].first
    assert_equal "video", media["type"]
    assert_equal 5000, media["duration_ms"]
    refute media.key?("variants"), "a video_info with no variants drops the compacted variants key"

    video = Xbookmark::X::Expansions.new(env).bookmarks.first.media.first
    assert_nil Xbookmark::Media::VariantPicker.best_video_url(video),
               "no variants means VariantPicker finds no playable mp4"
  end

  it "references a quoted id without an object and derives the id from the quoted result" do
    no_object = {
      "__typename" => "Tweet", "rest_id" => "3001",
      "legacy" => { "id_str" => "3001", "full_text" => "q", "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
                    "quoted_status_id_str" => "7777" }
    }
    env = single_entry_envelope(no_object)
    assert_equal [{ "type" => "quoted", "id" => "7777" }], env["data"].first["referenced_tweets"]
    assert_empty env["includes"]["tweets"]

    derived = {
      "__typename" => "Tweet", "rest_id" => "3002",
      "legacy" => { "id_str" => "3002", "full_text" => "q", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" },
      "quoted_status_result" => { "result" => {
        "__typename" => "Tweet", "rest_id" => "6666",
        "legacy" => { "id_str" => "6666", "full_text" => "quoted body", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
      } }
    }
    env2 = single_entry_envelope(derived)
    assert_equal "6666", env2["data"].first["referenced_tweets"].first["id"]
    assert_equal %w[6666], env2["includes"]["tweets"].map { |t| t["id"] }
  end

  it "ignores an unresolvable quoted_status_result" do
    result = {
      "__typename" => "Tweet", "rest_id" => "3003",
      "legacy" => { "id_str" => "3003", "full_text" => "q", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" },
      "quoted_status_result" => { "result" => { "__typename" => "Tweet", "legacy" => {} } }
    }
    env = single_entry_envelope(result)
    assert_empty env["data"].first["referenced_tweets"]
    assert_empty env["includes"]["tweets"]
  end

  # ---- hostile GraphQL shapes (High 2/3: one bad element must not crash) ----

  it "treats a non-Hash payload as an empty envelope" do
    env = described_class.new([1, 2, 3]).envelope
    assert_empty env["data"]
    refute env["meta"].key?("next_token")
  end

  it "survives a non-Hash data shape without raising" do
    env = described_class.new({ "data" => [] }).envelope
    assert_empty env["data"]
  end

  it "skips non-Hash instructions, entries, and timeline items" do
    payload = {
      "data" => { "bookmark_timeline_v2" => { "timeline" => { "instructions" => [
        "junk",
        { "type" => "TimelineAddEntries", "entries" => [
          "tombstone",
          { "content" => "not-a-hash" },
          { "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => "nope" } },
          { "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => {
            "itemType" => "TimelineTweet", "tweet_results" => { "result" => {
              "__typename" => "Tweet", "rest_id" => "1",
              "legacy" => { "id_str" => "1", "full_text" => "ok", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
            } } } } }
        ] }
      ] } } }
    }
    assert_equal %w[1], described_class.new(payload).envelope["data"].map { |t| t["id"] }
  end

  it "ignores non-Hash media, variant, and url entries" do
    result = {
      "__typename" => "Tweet", "rest_id" => "2",
      "legacy" => {
        "id_str" => "2", "full_text" => "t", "created_at" => "Thu Jan 01 00:00:00 +0000 2026",
        "extended_entities" => { "media" => ["junk", {
          "media_key" => "v1", "type" => "video", "media_url_https" => "https://x/p.jpg",
          "video_info" => { "variants" => ["nope", { "bitrate" => 1, "content_type" => "video/mp4", "url" => "https://x/v.mp4" }] }
        }] },
        "entities" => { "urls" => ["bad", { "url" => "u", "expanded_url" => "e" }] }
      }
    }
    env = single_entry_envelope(result)
    media = env["includes"]["media"]
    assert_equal %w[v1], media.map { |m| m["media_key"] }
    assert_equal 1, media.first["variants"].size
    assert_equal ["e"], env["data"].first["entities"]["urls"].map { |u| u["expanded_url"] }
  end

  it "drops a non-Hash tweet or quoted result instead of crashing" do
    wrapped_non_hash = { "__typename" => "TweetWithVisibilityResults", "tweet" => "garbage" }
    assert_empty single_entry_envelope(wrapped_non_hash)["data"]

    with_bad_quote = {
      "__typename" => "Tweet", "rest_id" => "3",
      "legacy" => { "id_str" => "3", "full_text" => "q", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" },
      "quoted_status_result" => { "result" => "garbage" }
    }
    env = single_entry_envelope(with_bad_quote)
    assert_empty env["data"].first["referenced_tweets"]
    assert_empty env["includes"]["tweets"]
  end

  it "omits a non-String created_at instead of raising TypeError or emitting a non-ISO8601 value" do
    result = {
      "__typename" => "Tweet", "rest_id" => "4",
      "legacy" => { "id_str" => "4", "full_text" => "t", "created_at" => 1_735_689_600 }
    }
    env = nil
    capture_stderr { env = single_entry_envelope(result) }
    refute env["data"].first.key?("created_at"),
           "a non-ISO8601 created_at would later mark the bookmark a permanent error, so drop it"
  end

  it "omits an unparseable created_at and warns" do
    result = {
      "__typename" => "Tweet", "rest_id" => "4001",
      "legacy" => { "id_str" => "4001", "full_text" => "t", "created_at" => "not-a-date" }
    }
    env = nil
    err = capture_stderr { env = single_entry_envelope(result) }
    refute env["data"].first.key?("created_at")
    assert_match(/dropping unparseable created_at/, err)
  end

  it "omits created_at when the source has none" do
    result = { "__typename" => "Tweet", "rest_id" => "4002", "legacy" => { "id_str" => "4002", "full_text" => "t" } }
    refute single_entry_envelope(result)["data"].first.key?("created_at")
  end

  # ---- single-tweet envelope (get_tweet parity) ----

  it "normalizes a TweetResultByRestId payload into a single-tweet envelope" do
    detail = fixture_json("browser", "tweet_detail.json")
    env = described_class.new(detail).single_tweet_envelope
    assert_equal %w[1001], env["data"].map { |t| t["id"] }
    assert_equal({}, env["meta"])
    bm = Xbookmark::X::Expansions.new(env).bookmarks.first
    assert_equal "alice", bm.author_handle
    assert_equal "photo", bm.media.first.type
  end

  it "normalizes a TweetDetail threaded-conversation payload" do
    result = {
      "__typename" => "Tweet", "rest_id" => "5001",
      "legacy" => { "id_str" => "5001", "full_text" => "threaded", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
    }
    entry = { "content" => { "itemContent" => { "itemType" => "TimelineTweet", "tweet_results" => { "result" => result } } } }
    instructions = [{ "type" => "TimelineAddEntries", "entries" => [entry] }]
    payload = { "data" => { "threaded_conversation_with_injections_v2" => { "instructions" => instructions } } }
    env = described_class.new(payload).single_tweet_envelope
    assert_equal(%w[5001], env["data"].map { |t| t["id"] })
  end

  def thread_detail_payload(*ids)
    entries = ids.map do |id|
      result = {
        "__typename" => "Tweet", "rest_id" => id,
        "legacy" => { "id_str" => id, "full_text" => "t#{id}", "created_at" => "Thu Jan 01 00:00:00 +0000 2026" }
      }
      { "content" => { "itemContent" => { "itemType" => "TimelineTweet", "tweet_results" => { "result" => result } } } }
    end
    instructions = [{ "type" => "TimelineAddEntries", "entries" => entries }]
    { "data" => { "threaded_conversation_with_injections_v2" => { "instructions" => instructions } } }
  end

  it "selects the requested reply out of a TweetDetail thread, not the thread root" do
    # Thread root 5000 precedes the focal reply 5001 in the conversation.
    payload = thread_detail_payload("5000", "5001")
    env = described_class.new(payload).single_tweet_envelope("5001")
    assert_equal(%w[5001], env["data"].map { |t| t["id"] }, "resync must return the focal reply, not the root")
  end

  it "returns an empty single-tweet envelope when the requested id is absent from the thread" do
    # Better to report the tweet as unavailable than to resync the wrong tweet.
    payload = thread_detail_payload("5000", "5001")
    env = described_class.new(payload).single_tweet_envelope("9999")
    assert_empty env["data"]
  end

  it "returns an empty single-tweet envelope when no tweet is present" do
    env = described_class.new({}).single_tweet_envelope
    assert_empty env["data"]
    assert_equal({}, env["meta"])
  end

  # ---- TweetDetail thread shape with interleaved non-tweet entries ----
  # The real conversation timeline interleaves cursor and module entries between
  # the TimelineTweet entries; tweet_detail_results must skip them (normalizer.rb
  # #tweet_detail_results) when selecting the focal tweet.

  it "selects the focal reply from a real thread fixture, skipping cursor and module entries" do
    thread = fixture_json("browser", "tweet_thread.json")
    env = described_class.new(thread).single_tweet_envelope("5001")
    assert_equal %w[5001], env["data"].map { |t| t["id"] }, "the focal reply is returned, not the root or a module reply"
    bm = Xbookmark::X::Expansions.new(env).bookmarks.first
    assert_equal "bob", bm.author_handle
    assert_equal "5000", bm.in_reply_to_tweet_id
  end

  it "falls back to the first thread tweet when no id is requested, ignoring cursor/module entries" do
    thread = fixture_json("browser", "tweet_thread.json")
    env = described_class.new(thread).single_tweet_envelope
    assert_equal %w[5000], env["data"].map { |t| t["id"] }, "the leading TimelineTweet wins; the Top cursor before it is skipped"
  end

  it "does not surface a tweet nested inside a TimelineTimelineModule entry" do
    # A module's inner tweet is not a top-level TimelineTweet entry, so it is not a
    # resync target — requesting it reports the tweet unavailable rather than the
    # wrong tweet.
    thread = fixture_json("browser", "tweet_thread.json")
    env = described_class.new(thread).single_tweet_envelope("5002")
    assert_empty env["data"]
  end
end
