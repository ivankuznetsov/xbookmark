# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/graphql_capture"

class FakeRequest
  def initialize(url, raises: false)
    @url = url
    @raises = raises
  end

  def url
    raise "request gone" if @raises

    @url
  end
end

class FakeResponse
  def initialize(body)
    @body = body
  end

  attr_reader :body
end

class FakeExchange
  attr_reader :id

  def initialize(url:, body: nil, id: nil, request_raises: false, has_response: true)
    @request = FakeRequest.new(url, raises: request_raises)
    @response = has_response ? FakeResponse.new(body) : nil
    @id = id
  end

  attr_reader :request, :response
end

class FakeNetwork
  def initialize(traffic: [], raises: false)
    @traffic = traffic
    @raises = raises
  end

  def traffic
    raise "cdp gone" if @raises

    @traffic
  end
end

class FakeCapturePage
  def initialize(network)
    @network = network
  end

  attr_reader :network
end

describe Xbookmark::Browser::GraphqlCapture do
  def gql(cursor)
    JSON.generate({ "cursor" => cursor })
  end

  def page_with(exchanges, raises: false)
    FakeCapturePage.new(FakeNetwork.new(traffic: exchanges, raises: raises))
  end

  it "returns parsed Bookmarks responses and ignores unrelated requests" do
    exchanges = [
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/Bookmarks?x=1", body: gql("c1"), id: 1),
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/HomeTimeline", body: gql("nope"), id: 2),
      FakeExchange.new(url: "https://pbs.twimg.com/media/x.jpg", body: "binary", id: 3)
    ]
    capture = described_class.new(page_with(exchanges))

    bodies = capture.drain_bookmarks
    assert_equal ["c1"], bodies.map { |b| b["cursor"] }
  end

  it "does not return the same exchange twice across drains" do
    ex = FakeExchange.new(url: "https://x.com/i/api/graphql/abc/Bookmarks", body: gql("c1"), id: 7)
    page = page_with([ex])
    capture = described_class.new(page)

    assert_equal ["c1"], capture.drain_bookmarks.map { |b| b["cursor"] }
    assert_empty capture.drain_bookmarks
  end

  it "captures single-tweet operations" do
    exchanges = [
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/TweetResultByRestId", body: gql("t1"), id: 1),
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/TweetDetail", body: gql("t2"), id: 2)
    ]
    capture = described_class.new(page_with(exchanges))
    assert_equal %w[t1 t2], capture.drain_tweets.map { |b| b["cursor"] }
  end

  it "skips exchanges with empty or unparseable bodies" do
    exchanges = [
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/Bookmarks", body: "", id: 1),
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/Bookmarks", body: "{not json", id: 2),
      FakeExchange.new(url: "https://x.com/i/api/graphql/abc/Bookmarks", has_response: false, id: 3)
    ]
    assert_empty described_class.new(page_with(exchanges)).drain_bookmarks
  end

  it "tolerates an exchange whose request url raises" do
    exchanges = [FakeExchange.new(url: "x", body: gql("c1"), id: 1, request_raises: true)]
    assert_empty described_class.new(page_with(exchanges)).drain_bookmarks
  end

  it "returns nothing when reading network traffic raises" do
    assert_empty described_class.new(page_with([], raises: true)).drain_bookmarks
  end

  it "falls back to object identity when an exchange has no id" do
    no_id = Class.new do
      def request = Struct.new(:url).new("https://x.com/i/api/graphql/abc/Bookmarks")
      def response = Struct.new(:body).new(JSON.generate({ "cursor" => "c1" }))
    end.new
    capture = described_class.new(page_with([no_id]))
    assert_equal ["c1"], capture.drain_bookmarks.map { |b| b["cursor"] }
    assert_empty capture.drain_bookmarks
  end
end
