# frozen_string_literal: true

require "test_helper"

require "ostruct"
require "xbookmark/enrich/link_fetcher"

describe Xbookmark::Enrich::LinkFetcher do
  LinkFetcherFakeResponse = Struct.new(:ok, :body, :url, keyword_init: true) do
    def success?
      ok
    end

    def env
      OpenStruct.new(url: URI(url))
    end
  end

  LinkFetcherFakeConnection = Struct.new(:response, :seen_timeout, keyword_init: true) do
    def get(_url)
      req = OpenStruct.new(options: OpenStruct.new)
      yield req if block_given?
      self.seen_timeout = req.options.timeout
      response
    end
  end

  it "rejects unsafe URL schemes, invalid URLs, empty hosts, and private address ranges" do
    fetcher = described_class.new
    fetcher.stubs(:resolve).with("example.com").returns(["93.184.216.34"])
    fetcher.stubs(:resolve).with("internal.test").returns(["10.0.0.1"])
    fetcher.stubs(:resolve).with("unclassifiable.test").returns(["not-an-ip"])

    refute fetcher.safe_url?("ftp://example.com/file")
    refute fetcher.safe_url?("http://[bad")
    refute fetcher.safe_url?("https://")
    refute fetcher.safe_url?("http://internal.test/page")
    refute fetcher.safe_url?("http://unclassifiable.test/page")
    assert fetcher.safe_url?("https://example.com/page")
  end

  it "accepts literal public IPs without DNS and fails closed when DNS raises" do
    fetcher = described_class.new
    Resolv.stubs(:getaddresses).with("dns-fails.test").raises(Resolv::ResolvError)

    assert_equal ["8.8.8.8"], fetcher.send(:resolve, "8.8.8.8")
    refute fetcher.safe_url?("https://dns-fails.test/article")
  end

  it "fetches readable article fields only when both original and final URLs are safe" do
    response = LinkFetcherFakeResponse.new(
      ok: true,
      url: "https://example.com/article",
      body: <<~HTML
        <html>
          <head><title>  Useful Article  </title><meta name="author" content="Ada"></head>
          <body><main><p>First paragraph.</p><p>Second paragraph.</p></main></body>
        </html>
      HTML
    )
    conn = LinkFetcherFakeConnection.new(response: response)
    fetcher = described_class.new(conn: conn)
    fetcher.stubs(:resolve).with("example.com").returns(["93.184.216.34"])

    result = fetcher.fetch("https://example.com/article")

    assert_equal "https://example.com/article", result[:url]
    assert_equal "https://example.com/article", result[:final_url]
    assert_equal "Useful Article", result[:title]
    assert_equal "Ada", result[:byline]
    assert_equal "First paragraph.\n\nSecond paragraph.", result[:text]
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, result[:fetched_at])
    assert_equal 20, conn.seen_timeout
  end

  it "returns nil for non-success responses, unsafe redirects, and connection errors" do
    fetcher = described_class.new(conn: LinkFetcherFakeConnection.new(response: LinkFetcherFakeResponse.new(ok: false, url: "https://example.com", body: "")))
    fetcher.stubs(:resolve).with("example.com").returns(["93.184.216.34"])
    assert_nil fetcher.fetch("https://example.com")

    redirected = described_class.new(conn: LinkFetcherFakeConnection.new(response: LinkFetcherFakeResponse.new(ok: true, url: "http://127.0.0.1/secret", body: "<p>x</p>")))
    redirected.stubs(:resolve).with("example.com").returns(["93.184.216.34"])
    redirected.stubs(:resolve).with("127.0.0.1").returns(["127.0.0.1"])
    assert_nil redirected.fetch("https://example.com")

    broken_conn = Class.new do
      def get(_url)
        raise Faraday::ConnectionFailed, "boom"
      end
    end.new
    broken = described_class.new(conn: broken_conn)
    broken.stubs(:resolve).with("example.com").returns(["93.184.216.34"])
    assert_nil broken.fetch("https://example.com")
  end

  it "builds a default Faraday client with the xbookmark user agent" do
    fetcher = described_class.new

    conn = fetcher.send(:http)

    assert_equal "xbookmark/1.0 (link-readability-fetcher)", conn.headers["User-Agent"]
  end
end
