# frozen_string_literal: true

require "ostruct"
require "xbookmark/enrich/link_fetcher"

RSpec.describe Xbookmark::Enrich::LinkFetcher do
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
    allow(fetcher).to receive(:resolve).with("example.com").and_return(["93.184.216.34"])
    allow(fetcher).to receive(:resolve).with("internal.test").and_return(["10.0.0.1"])
    allow(fetcher).to receive(:resolve).with("unclassifiable.test").and_return(["not-an-ip"])

    expect(fetcher.safe_url?("ftp://example.com/file")).to be(false)
    expect(fetcher.safe_url?("http://[bad")).to be(false)
    expect(fetcher.safe_url?("https://")).to be(false)
    expect(fetcher.safe_url?("http://internal.test/page")).to be(false)
    expect(fetcher.safe_url?("http://unclassifiable.test/page")).to be(false)
    expect(fetcher.safe_url?("https://example.com/page")).to be(true)
  end

  it "accepts literal public IPs without DNS and fails closed when DNS raises" do
    fetcher = described_class.new
    allow(Resolv).to receive(:getaddresses).with("dns-fails.test").and_raise(Resolv::ResolvError)

    expect(fetcher.send(:resolve, "8.8.8.8")).to eq(["8.8.8.8"])
    expect(fetcher.safe_url?("https://dns-fails.test/article")).to be(false)
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
    allow(fetcher).to receive(:resolve).with("example.com").and_return(["93.184.216.34"])

    result = fetcher.fetch("https://example.com/article")

    expect(result).to include(
      url: "https://example.com/article",
      final_url: "https://example.com/article",
      title: "Useful Article",
      byline: "Ada",
      text: "First paragraph.\n\nSecond paragraph."
    )
    expect(result[:fetched_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    expect(conn.seen_timeout).to eq(20)
  end

  it "returns nil for non-success responses, unsafe redirects, and connection errors" do
    fetcher = described_class.new(conn: LinkFetcherFakeConnection.new(response: LinkFetcherFakeResponse.new(ok: false, url: "https://example.com", body: "")))
    allow(fetcher).to receive(:resolve).with("example.com").and_return(["93.184.216.34"])
    expect(fetcher.fetch("https://example.com")).to be_nil

    redirected = described_class.new(conn: LinkFetcherFakeConnection.new(response: LinkFetcherFakeResponse.new(ok: true, url: "http://127.0.0.1/secret", body: "<p>x</p>")))
    allow(redirected).to receive(:resolve).and_call_original
    allow(redirected).to receive(:resolve).with("example.com").and_return(["93.184.216.34"])
    expect(redirected.fetch("https://example.com")).to be_nil

    broken_conn = Class.new do
      def get(_url)
        raise Faraday::ConnectionFailed, "boom"
      end
    end.new
    broken = described_class.new(conn: broken_conn)
    allow(broken).to receive(:resolve).with("example.com").and_return(["93.184.216.34"])
    expect(broken.fetch("https://example.com")).to be_nil
  end

  it "builds a default Faraday client with the xbookmark user agent" do
    fetcher = described_class.new

    conn = fetcher.send(:http)

    expect(conn.headers["User-Agent"]).to eq("xbookmark/1.0 (link-readability-fetcher)")
  end
end
