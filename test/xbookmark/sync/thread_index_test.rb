# frozen_string_literal: true

require "test_helper"

require "ostruct"
require "xbookmark/sync/thread_index"
require "xbookmark/state/store"

describe Xbookmark::Sync::ThreadIndex do
  def bookmark(id:, conversation:, author: "alice", text: "Thread starter about practical taxonomy")
    OpenStruct.new(tweet_id: id, conversation_id: conversation, author_handle: author, text: text)
  end

  it "suppresses singleton self-conversations and emits readable thread targets for real threads" do
    singleton = bookmark(id: "1", conversation: "1")
    assert_nil described_class.new(bookmarks: [singleton]).thread_for(singleton)

    first = bookmark(id: "1", conversation: "c1")
    second = bookmark(id: "2", conversation: "c1")
    thread = described_class.new(bookmarks: [first, second]).thread_for(first)

    assert_equal "threads/thread-thread-starter-about-practical-taxonomy-c1", thread[:target]
    assert_equal "Thread: Thread starter about practical taxonomy", thread[:label]
    assert described_class.new(bookmarks: [first, second]).real_thread?(second)

    # Cross-author replies in the same conversation resolve to one thread page.
    third = bookmark(id: "3", conversation: "c1", author: "bob")
    cross = described_class.new(bookmarks: [first, third])
    assert_equal cross.thread_for(first)[:target], cross.thread_for(third)[:target]
  end

  it "derives counts from store payloads, corrupt payloads, and existing thread pages" do
    store = Xbookmark::State::Store.new(":memory:")
    payload = { "data" => [{ "id" => "1", "conversation_id" => "1" }], "includes" => {}, "meta" => {} }
    store.upsert_pending(tweet_id: "1", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z", payload: payload)
    store.instance_variable_get(:@db).execute("UPDATE bookmarks SET payload_json = ? WHERE tweet_id = ?", ["{bad", "1"])
    store.upsert_page(kind: "thread", slug: "1", path: "threads/1.md")

    thread = described_class.new(store: store).thread_for(bookmark(id: "1", conversation: "1", author: nil))

    assert_equal "threads/thread-thread-starter-about-practical-taxonomy-1", thread[:target]
  end

  it "can add a fetched page before the first bookmark is processed" do
    first = bookmark(id: "1", conversation: "c1")
    second = bookmark(id: "2", conversation: "c1")
    index = described_class.new

    index.add_bookmarks([first, second])

    assert_equal "threads/thread-thread-starter-about-practical-taxonomy-c1", index.thread_for(first)[:target]
  end
end
