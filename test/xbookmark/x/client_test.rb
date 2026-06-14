# frozen_string_literal: true

require "test_helper"

require "xbookmark/x/client"

describe Xbookmark::X::Client do
  def config_with(access_token: "TOKEN", expires_at: Time.now.to_i + 3600, refresh_token: nil)
    Struct::XbookmarkConfig.new(
      vault_path: "/tmp/v",
      state_db_path: "/tmp/v/.xbookmark/state.db",
      logs_dir: "/tmp/logs",
      scratch_dir: "/tmp/v/.xbookmark/scratch",
      x_client_id: "client123",
      x_client_secret: nil,
      x_redirect_uri: "http://127.0.0.1:7799/callback",
      x_user_id: "42",
      x_access_token: access_token,
      x_refresh_token: refresh_token,
      x_token_expires_at: expires_at,
      codex_bin: "codex",
      whisper_bin: nil,
      whisper_model: "base.en",
      qmd_bin: "qmd",
      daily_sync_time: "06:00",
      min_run_interval_hours: 20.0,
      aux_summaries: false,
      env_file: "/tmp/.env",
      verbose: false
    )
  end

  it "fetches the bookmarks endpoint and follows pagination" do
    page1 = Fixtures.bookmarks_page
    page2 = Fixtures.bookmarks_page2

    stub_request(:get, "https://api.twitter.com/2/users/42/bookmarks")
      .with(query: hash_including("max_results" => "50"))
      .to_return({ status: 200, body: page1.to_json, headers: { "Content-Type" => "application/json" } },
                 { status: 200, body: page2.to_json, headers: { "Content-Type" => "application/json" } })

    client = described_class.new(config: config_with)
    pages = client.bookmarks(user_id: "42").to_a
    assert_equal 2, pages.size
    assert_equal 3, pages.first["data"].size
  end

  it "raises RateLimited on 429" do
    stub_request(:get, %r{https://api.twitter.com/2/users/42/bookmarks})
      .to_return(status: 429, headers: { "x-rate-limit-reset" => "12345" }, body: '{"title":"Too Many Requests"}')

    client = described_class.new(config: config_with)
    assert_raises(Xbookmark::RateLimited) { client.bookmarks(user_id: "42").to_a }
  end

  it "transparently refreshes a near-expired token before issuing the request" do
    config = config_with(access_token: "OLD", expires_at: Time.now.to_i - 60, refresh_token: "REFRESH")

    stub_request(:post, "https://api.twitter.com/2/oauth2/token")
      .to_return(status: 200, body: { access_token: "NEW", refresh_token: "REFRESH", expires_in: 3600 }.to_json)

    fake_auth = mock("auth")
    refreshed = Xbookmark::X::Auth::AuthResult.new(
      env_file: "/tmp/.env", access_token: "NEW", refresh_token: "REFRESH", expires_at: Time.now.to_i + 3600
    )
    fake_auth.stubs(:refresh!).returns(refreshed)

    stub_request(:get, %r{api.twitter.com/2/users/42/bookmarks})
      .with(headers: { "Authorization" => "Bearer NEW" })
      .to_return(status: 200, body: Fixtures.bookmarks_page2.to_json)

    client = described_class.new(config: config, auth: fake_auth)
    pages = client.bookmarks(user_id: "42").to_a
    assert_equal "1004", pages.first["data"].first["id"]
    assert_equal "NEW", config.x_access_token
  end

  it "fetches individual tweets and conversation search results" do
    stub_request(:get, "https://api.twitter.com/2/tweets/123")
      .with(query: hash_including("expansions" => "author_id"))
      .to_return(status: 200, body: { "data" => { "id" => "123" } }.to_json)
    stub_request(:get, "https://api.twitter.com/2/tweets/search/recent")
      .with(query: hash_including("query" => "conversation_id:abc", "max_results" => "10"))
      .to_return(status: 200, body: { "data" => [{ "id" => "1" }] }.to_json)

    client = described_class.new(config: config_with)

    assert_equal "123", client.get_tweet("123", expansions: "author_id")["data"]["id"]
    assert_equal "1", client.conversation("abc", max_results: 10)["data"].first["id"]
  end

  it "classifies unavailable individual tweets separately from global source outages" do
    stub_request(:get, %r{api.twitter.com/2/tweets/deleted})
      .to_return(status: 404, body: "not found")

    error = assert_raises(Xbookmark::SourceUnavailable) { described_class.new(config: config_with).get_tweet("deleted") }
    assert_match(/X source unavailable \(404\): not found/, error.message)
  end

  it "refreshes once after a 401 response and retries with the new token" do
    config = config_with(access_token: "OLD", refresh_token: "REFRESH")
    fake_auth = mock("auth")
    refreshed = Xbookmark::X::Auth::AuthResult.new(
      env_file: "/tmp/.env", access_token: "NEW", refresh_token: "ROTATED", expires_at: Time.now.to_i + 3600
    )
    fake_auth.stubs(:refresh!).returns(refreshed)
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return({ status: 401, body: "expired" },
                 { status: 200, body: { "data" => { "id" => "123" } }.to_json })

    client = described_class.new(config: config, auth: fake_auth)

    assert_equal "123", client.get_tweet("123")["data"]["id"]
    assert_equal "NEW", config.x_access_token
    assert_equal "ROTATED", config.x_refresh_token
  end

  it "raises AuthError when the post-refresh retry still fails" do
    config = config_with(access_token: "OLD", refresh_token: "REFRESH")
    fake_auth = mock("auth")
    fake_auth.stubs(:refresh!)
      .returns(Xbookmark::X::Auth::AuthResult.new(env_file: "/tmp/.env", access_token: "NEW", refresh_token: "REFRESH", expires_at: Time.now.to_i + 3600))
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return({ status: 401, body: "expired" },
                 { status: 403, body: "still forbidden" })

    client = described_class.new(config: config, auth: fake_auth)

    error = assert_raises(Xbookmark::AuthError) { client.get_tweet("123") }
    assert_match(/X API auth failed \(403\): still forbidden/, error.message)
  end

  it "raises TransientError for non-auth, non-rate-limit API failures" do
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return(status: 503, body: "down")

    error = assert_raises(Xbookmark::TransientError) { described_class.new(config: config_with).get_tweet("123") }
    assert_match(/X API error 503: down/, error.message)
  end

  it "keeps bookmarks endpoint permission failures as global source errors" do
    stub_request(:get, %r{api.twitter.com/2/users/42/bookmarks})
      .to_return(status: 403, body: "forbidden")

    error = assert_raises(Xbookmark::TransientError) { described_class.new(config: config_with).bookmarks(user_id: "42").to_a }
    assert_match(/X API error 403: forbidden/, error.message)
  end

  it "wraps X transport failures as transient source errors" do
    stub_request(:get, %r{api.twitter.com/2/users/42/bookmarks})
      .to_raise(Faraday::ConnectionFailed.new("network down"))

    error = assert_raises(Xbookmark::TransientError) { described_class.new(config: config_with).bookmarks(user_id: "42").to_a }
    assert_match(/X API transport failed: network down/, error.message)
  end
end
