# frozen_string_literal: true

require "xbookmark/x/auth"

RSpec.describe Xbookmark::X::Auth do
  def fake_config(env_path:, refresh_token: nil, expires_at: nil)
    Xbookmark::Config.send(:remove_const, :ALREADY) if false # noop guard
    Struct::XbookmarkConfig.new(
      vault_path: "/tmp/v",
      state_db_path: "/tmp/v/.xbookmark/state.db",
      logs_dir: "/tmp/logs",
      scratch_dir: "/tmp/v/.xbookmark/scratch",
      x_client_id: "client123",
      x_client_secret: nil,
      x_redirect_uri: "http://127.0.0.1:7799/callback",
      x_user_id: "42",
      x_access_token: "old-access",
      x_refresh_token: refresh_token,
      x_token_expires_at: expires_at,
      codex_bin: "codex",
      whisper_bin: nil,
      whisper_model: "base.en",
      qmd_bin: "qmd",
      daily_sync_time: "06:00",
      min_run_interval_hours: 20.0,
      env_file: env_path,
      verbose: false
    )
  end

  it "writes tokens to .env after a successful exchange" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123\nX_REDIRECT_URI=http://127.0.0.1:7799/callback\n")
      config = fake_config(env_path: env_path)
      auth = described_class.new(config, opener: false, env_path: env_path)
      auth.write_tokens!({
        "access_token" => "ACC", "refresh_token" => "REF", "expires_in" => 7200
      })
      contents = File.read(env_path)
      expect(contents).to include("X_ACCESS_TOKEN=ACC")
      expect(contents).to include("X_REFRESH_TOKEN=REF")
      expect(contents).to match(/X_TOKEN_EXPIRES_AT=\d+/)
    end
  end

  it "preserves the refresh token when the response omits it" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_REFRESH_TOKEN=KEEP\n")
      config = fake_config(env_path: env_path, refresh_token: "KEEP")
      auth = described_class.new(config, opener: false, env_path: env_path)
      auth.write_tokens!({ "access_token" => "ACC2", "expires_in" => 60 }, preserve_refresh: true)
      expect(File.read(env_path)).to include("X_REFRESH_TOKEN=KEEP")
    end
  end

  it "PKCE challenge is base64url(SHA256(verifier)) without padding" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env"), opener: false, env_path: "/tmp/.env")
    challenge = auth.pkce_challenge("a" * 64)
    expect(challenge).to match(/\A[A-Za-z0-9_-]+\z/)
    expect(challenge).not_to include("=")
  end

  it "refresh! calls token endpoint and persists rotated tokens" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123\nX_REFRESH_TOKEN=OLD\n")
      config = fake_config(env_path: env_path, refresh_token: "OLD", expires_at: Time.now.to_i - 100)
      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "OLD"))
        .to_return(status: 200, body: { access_token: "NEW", refresh_token: "ROTATED", expires_in: 3600 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      auth = described_class.new(config, opener: false, env_path: env_path)
      result = auth.refresh!
      expect(result.access_token).to eq("NEW")
      expect(result.refresh_token).to eq("ROTATED")
      expect(File.read(env_path)).to include("X_ACCESS_TOKEN=NEW")
      expect(File.read(env_path)).to include("X_REFRESH_TOKEN=ROTATED")
    end
  end

  it "raises AuthError when token endpoint returns non-2xx" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_REFRESH_TOKEN=OLD\n")
      config = fake_config(env_path: env_path, refresh_token: "OLD")
      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .to_return(status: 400, body: '{"error":"invalid_grant"}')

      auth = described_class.new(config, opener: false, env_path: env_path)
      expect { auth.refresh! }.to raise_error(Xbookmark::AuthError, /Token refresh failed/)
    end
  end
end
