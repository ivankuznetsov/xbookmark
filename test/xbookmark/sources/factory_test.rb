# frozen_string_literal: true

require "test_helper"
require "xbookmark/sources/factory"
require "xbookmark/state/store"

describe Xbookmark::Sources::Factory do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  def config(source)
    Struct::XbookmarkConfig.new(vault_path: "/tmp/wiki", state_db_path: ":memory:", source: source,
                                x_user_id: "42", x_client_id: "c")
  end

  it "builds a single API source by default" do
    sources = described_class.build(config: config("api"), store: store)
    assert_equal [Xbookmark::X::Client], sources.map(&:class)
  end

  it "builds a single browser source" do
    sources = described_class.build(config: config("browser"), store: store)
    assert_equal [Xbookmark::Browser::Source], sources.map(&:class)
  end

  it "builds the API source first, then the browser source, for both" do
    sources = described_class.build(config: config("both"), store: store)
    assert_equal [Xbookmark::X::Client, Xbookmark::Browser::Source], sources.map(&:class)
  end

  it "raises ConfigError for an unrecognized source instead of silently defaulting to api" do
    error = assert_raises(Xbookmark::ConfigError) { described_class.build(config: config("nonsense"), store: store) }
    assert_match(/Unknown source/, error.message)
  end

  it "only returns sources that satisfy the bookmark-source contract" do
    [config("api"), config("browser"), config("both")].each do |cfg|
      described_class.build(config: cfg, store: store).each do |source|
        assert_respond_to source, :bookmarks
        assert_respond_to source, :get_tweet
      end
    end
  end

  it "rejects a source that does not satisfy the contract" do
    described_class.stubs(:api_source).returns(Object.new)
    error = assert_raises(Xbookmark::ConfigError) { described_class.build(config: config("api"), store: store) }
    assert_match(/does not satisfy the bookmark-source contract/, error.message)
  end
end
