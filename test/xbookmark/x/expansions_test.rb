# frozen_string_literal: true

require "test_helper"

require "xbookmark/x/expansions"

describe Xbookmark::X::Expansions do
  let(:payload) { Fixtures.bookmarks_page }

  it "parses bookmarks with author handle, photo media, and quoted tweet" do
    bookmarks = described_class.new(payload).bookmarks
    assert_equal 3, bookmarks.size

    first = bookmarks[0]
    assert_equal "1001", first.tweet_id
    assert_equal "alice", first.author_handle
    assert_equal 1, first.media.size
    assert first.media.first.image?
    assert_equal "https://example.com/a", first.urls.first[:expanded_url]

    video = bookmarks[1]
    assert_equal "video", video.media.first.type
    assert video.media.first.video?

    quoting = bookmarks[2]
    assert_equal "9999", quoting.quoted_tweet_id
    assert_equal "the quoted tweet", quoting.quoted_tweet["text"]
  end

  it "exposes the next pagination token" do
    assert_equal "page2", described_class.new(payload).next_token
  end
end
