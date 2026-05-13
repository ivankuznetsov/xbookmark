# frozen_string_literal: true

require "xbookmark/x/expansions"

RSpec.describe Xbookmark::X::Expansions do
  let(:payload) { Fixtures.bookmarks_page }

  it "parses bookmarks with author handle, photo media, and quoted tweet" do
    bookmarks = described_class.new(payload).bookmarks
    expect(bookmarks.size).to eq(3)

    first = bookmarks[0]
    expect(first.tweet_id).to eq("1001")
    expect(first.author_handle).to eq("alice")
    expect(first.media.size).to eq(1)
    expect(first.media.first.image?).to eq(true)
    expect(first.urls.first[:expanded_url]).to eq("https://example.com/a")

    video = bookmarks[1]
    expect(video.media.first.type).to eq("video")
    expect(video.media.first.video?).to eq(true)

    quoting = bookmarks[2]
    expect(quoting.quoted_tweet_id).to eq("9999")
    expect(quoting.quoted_tweet["text"]).to eq("the quoted tweet")
  end

  it "exposes the next pagination token" do
    expect(described_class.new(payload).next_token).to eq("page2")
  end
end
