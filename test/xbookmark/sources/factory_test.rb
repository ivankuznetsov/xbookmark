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

  it "treats an unrecognized/nil source as api (defensive default)" do
    sources = described_class.build(config: config(nil), store: store)
    assert_equal [Xbookmark::X::Client], sources.map(&:class)
  end
end
