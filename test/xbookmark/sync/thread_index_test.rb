# frozen_string_literal: true

require "test_helper"

require "ostruct"
require "xbookmark/sync/thread_index"
require "xbookmark/state/store"

describe Xbookmark::Sync::ThreadIndex do
  def bookmark(id:, conversation:, author: "alice")
    OpenStruct.new(tweet_id: id, conversation_id: conversation, author_handle: author)
  end

  it "suppresses singleton self-conversations and emits readable thread targets for real threads" do
    singleton = bookmark(id: "1", conversation: "1")
    assert_nil described_class.new(bookmarks: [singleton]).thread_for(singleton)

    first = bookmark(id: "1", conversation: "c1")
    second = bookmark(id: "2", conversation: "c1")
    thread = described_class.new(bookmarks: [first, second]).thread_for(first)

    assert_equal "threads/alice-c1-thread", thread[:target]
    assert described_class.new(bookmarks: [first, second]).real_thread?(second)
  end

  it "derives counts from store payloads, corrupt payloads, and existing thread pages" do
    store = Xbookmark::State::Store.new(":memory:")
    payload = { "data" => [{ "id" => "1", "conversation_id" => "1" }], "includes" => {}, "meta" => {} }
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z", payload: payload)
    store.instance_variable_get(:@db).execute("UPDATE bookmarks SET payload_json = ? WHERE tweet_id = ?", ["{bad", "1"])
    store.upsert_page(kind: "thread", slug: "1", path: "threads/1.md")

    thread = described_class.new(store: store).thread_for(bookmark(id: "1", conversation: "1", author: nil))

    assert_equal "threads/thread-1", thread[:target]
  end
end
