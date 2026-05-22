# frozen_string_literal: true

require "xbookmark/x/client"

RSpec.describe Xbookmark::X::Client do
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
    expect(pages.size).to eq(2)
    expect(pages.first["data"].size).to eq(3)
  end

  it "raises RateLimited on 429" do
    stub_request(:get, %r{https://api.twitter.com/2/users/42/bookmarks})
      .to_return(status: 429, headers: { "x-rate-limit-reset" => "12345" }, body: '{"title":"Too Many Requests"}')

    client = described_class.new(config: config_with)
    expect { client.bookmarks(user_id: "42").to_a }.to raise_error(Xbookmark::RateLimited)
  end

  it "transparently refreshes a near-expired token before issuing the request" do
    config = config_with(access_token: "OLD", expires_at: Time.now.to_i - 60, refresh_token: "REFRESH")

    stub_request(:post, "https://api.twitter.com/2/oauth2/token")
      .to_return(status: 200, body: { access_token: "NEW", refresh_token: "REFRESH", expires_in: 3600 }.to_json)

    fake_auth = instance_double(Xbookmark::X::Auth)
    refreshed = Xbookmark::X::Auth::AuthResult.new(
      env_file: "/tmp/.env", access_token: "NEW", refresh_token: "REFRESH", expires_at: Time.now.to_i + 3600
    )
    allow(fake_auth).to receive(:refresh!).and_return(refreshed)

    stub_request(:get, %r{api.twitter.com/2/users/42/bookmarks})
      .with(headers: { "Authorization" => "Bearer NEW" })
      .to_return(status: 200, body: Fixtures.bookmarks_page2.to_json)

    client = described_class.new(config: config, auth: fake_auth)
    pages = client.bookmarks(user_id: "42").to_a
    expect(pages.first["data"].first["id"]).to eq("1004")
    expect(config.x_access_token).to eq("NEW")
  end

  it "fetches individual tweets and conversation search results" do
    stub_request(:get, "https://api.twitter.com/2/tweets/123")
      .with(query: hash_including("expansions" => "author_id"))
      .to_return(status: 200, body: { "data" => { "id" => "123" } }.to_json)
    stub_request(:get, "https://api.twitter.com/2/tweets/search/recent")
      .with(query: hash_including("query" => "conversation_id:abc", "max_results" => "10"))
      .to_return(status: 200, body: { "data" => [{ "id" => "1" }] }.to_json)

    client = described_class.new(config: config_with)

    expect(client.get_tweet("123", expansions: "author_id")["data"]["id"]).to eq("123")
    expect(client.conversation("abc", max_results: 10)["data"].first["id"]).to eq("1")
  end

  it "refreshes once after a 401 response and retries with the new token" do
    config = config_with(access_token: "OLD", refresh_token: "REFRESH")
    fake_auth = instance_double(Xbookmark::X::Auth)
    refreshed = Xbookmark::X::Auth::AuthResult.new(
      env_file: "/tmp/.env", access_token: "NEW", refresh_token: "ROTATED", expires_at: Time.now.to_i + 3600
    )
    allow(fake_auth).to receive(:refresh!).and_return(refreshed)
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return({ status: 401, body: "expired" },
                 { status: 200, body: { "data" => { "id" => "123" } }.to_json })

    client = described_class.new(config: config, auth: fake_auth)

    expect(client.get_tweet("123")["data"]["id"]).to eq("123")
    expect(config.x_access_token).to eq("NEW")
    expect(config.x_refresh_token).to eq("ROTATED")
  end

  it "raises AuthError when the post-refresh retry still fails" do
    config = config_with(access_token: "OLD", refresh_token: "REFRESH")
    fake_auth = instance_double(Xbookmark::X::Auth)
    allow(fake_auth).to receive(:refresh!)
      .and_return(Xbookmark::X::Auth::AuthResult.new(env_file: "/tmp/.env", access_token: "NEW", refresh_token: "REFRESH", expires_at: Time.now.to_i + 3600))
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return({ status: 401, body: "expired" },
                 { status: 403, body: "still forbidden" })

    client = described_class.new(config: config, auth: fake_auth)

    expect { client.get_tweet("123") }
      .to raise_error(Xbookmark::AuthError, /X API auth failed \(403\): still forbidden/)
  end

  it "raises TransientError for non-auth, non-rate-limit API failures" do
    stub_request(:get, %r{api.twitter.com/2/tweets/123})
      .to_return(status: 503, body: "down")

    expect { described_class.new(config: config_with).get_tweet("123") }
      .to raise_error(Xbookmark::TransientError, /X API error 503: down/)
  end
end
