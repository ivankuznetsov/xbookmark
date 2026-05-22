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
      aux_summaries: false,
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

  it "appends token keys to env files that do not end with a newline and tightens permissions" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123")
      config = fake_config(env_path: env_path)
      auth = described_class.new(config, opener: false, env_path: env_path)

      auth.write_tokens!({ "access_token" => "ACC", "expires_in" => 10 })

      expect(File.read(env_path)).to include("X_CLIENT_ID=client123\nX_ACCESS_TOKEN=ACC")
      expect(format("%o", File.stat(env_path).mode & 0o777)).to eq("600")
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

  it "writes tokens to the keystore when no env file is loaded" do
    keystore = Xbookmark::Keystore.new(backend: Xbookmark::Keystore::Memory.new)
    config = fake_config(env_path: nil)
    auth = described_class.new(config, opener: false, keystore: keystore)

    auth.write_tokens!({ "access_token" => "ACC", "refresh_token" => "REF", "expires_in" => 7200 })

    expect(keystore.get("X_ACCESS_TOKEN")).to eq("ACC")
    expect(keystore.get("X_REFRESH_TOKEN")).to eq("REF")
    expect(keystore.get("X_TOKEN_EXPIRES_AT")).to match(/\A\d+\z/)
  end

  it "keeps rotating tokens out of Keychain argv by using the stable user env file" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      backend = instance_double("KeychainBackend", name: "keychain")
      keychain = Xbookmark::Keystore.new(backend: backend)
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return(env_path)

      auth = described_class.new(fake_config(env_path: nil), opener: false, keystore: keychain)
      auth.write_tokens!({ "access_token" => "ACC", "refresh_token" => "REF", "expires_in" => 7200 })

      expect(File.read(env_path)).to include("X_ACCESS_TOKEN=ACC")
    end
  end

  it "PKCE challenge is base64url(SHA256(verifier)) without padding" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env"), opener: false, env_path: "/tmp/.env")
    challenge = auth.pkce_challenge("a" * 64)
    expect(challenge).to match(/\A[A-Za-z0-9_-]+\z/)
    expect(challenge).not_to include("=")
  end

  it "builds the OAuth authorize URL with the configured redirect, state, challenge, and scopes" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env"), opener: false, env_path: "/tmp/.env")

    uri = URI(auth.build_authorize_url(state: "STATE", challenge: "CHALLENGE"))
    params = URI.decode_www_form(uri.query).to_h

    expect(uri.to_s).to start_with("https://twitter.com/i/oauth2/authorize")
    expect(params).to include(
      "response_type" => "code",
      "client_id" => "client123",
      "redirect_uri" => "http://127.0.0.1:7799/callback",
      "state" => "STATE",
      "code_challenge" => "CHALLENGE",
      "code_challenge_method" => "S256"
    )
    expect(params["scope"].split).to include("tweet.read", "users.read", "bookmark.read", "offline.access")
  end

  it "runs the login flow through opener, callback, exchange, persistence, and result shaping" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123\n")
      opened = nil
      config = fake_config(env_path: env_path)
      auth = described_class.new(config, opener: ->(url) { opened = url }, env_path: env_path)
      allow(auth).to receive(:wait_for_callback).and_return("CODE")
      allow(auth).to receive(:exchange_code_for_token)
        .and_return({ "access_token" => "ACC", "refresh_token" => "REF", "expires_in" => 20 })

      result = nil
      capture_stderr { result = auth.login }

      expect(opened).to include("https://twitter.com/i/oauth2/authorize")
      expect(result.env_file).to eq(env_path)
      expect(result.access_token).to eq("ACC")
      expect(result.refresh_token).to eq("REF")
      expect(File.read(env_path)).to include("X_ACCESS_TOKEN=ACC")
    end
  end

  it "does not open a browser when opener is false and swallows opener failures" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env"), opener: false, env_path: "/tmp/.env")
    expect(auth.try_open("https://example.com")).to be_nil

    broken = described_class.new(fake_config(env_path: "/tmp/.env"), opener: ->(_) { raise "no gui" }, env_path: "/tmp/.env")
    expect { broken.try_open("https://example.com") }.not_to raise_error
  end

  it "uses xdg-open or open when available and falls through when no opener exists" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env"), env_path: "/tmp/.env")
    allow(auth).to receive(:which).with("xdg-open").and_return("/usr/bin/xdg-open")
    expect(auth).to receive(:system).with("xdg-open", "https://example.com", out: File::NULL, err: File::NULL)
    auth.try_open("https://example.com")

    mac_auth = described_class.new(fake_config(env_path: "/tmp/.env"), env_path: "/tmp/.env")
    allow(mac_auth).to receive(:which).with("xdg-open").and_return(nil)
    allow(mac_auth).to receive(:which).with("open").and_return("/usr/bin/open")
    expect(mac_auth).to receive(:system).with("open", "https://example.com", out: File::NULL, err: File::NULL)
    mac_auth.try_open("https://example.com")

    none = described_class.new(fake_config(env_path: "/tmp/.env"), env_path: "/tmp/.env")
    allow(none).to receive(:which).and_return(nil)
    expect(none.try_open("https://example.com")).to be_nil
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

  it "sends HTTP basic auth while refreshing confidential-client tokens" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123\nX_REFRESH_TOKEN=OLD\n")
      config = fake_config(env_path: env_path, refresh_token: "OLD")
      config.x_client_secret = "secret"
      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .with(headers: { "Authorization" => /^Basic / },
              body: hash_including("grant_type" => "refresh_token", "refresh_token" => "OLD"))
        .to_return(status: 200, body: { access_token: "NEW", refresh_token: "ROTATED", expires_in: 3600 }.to_json)

      result = described_class.new(config, opener: false, env_path: env_path).refresh!

      expect(result.access_token).to eq("NEW")
    end
  end

  it "raises before refresh when no refresh token is configured" do
    auth = described_class.new(fake_config(env_path: "/tmp/.env", refresh_token: nil), opener: false, env_path: "/tmp/.env")

    expect { auth.refresh! }.to raise_error(Xbookmark::AuthError, /Missing refresh token/)
  end

  it "sends HTTP basic auth for confidential-client token exchange and rejects error bodies" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=client123\n")
      config = fake_config(env_path: env_path)
      config.x_client_secret = "secret"
      auth = described_class.new(config, opener: false, env_path: env_path)

      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .with(headers: { "Authorization" => /^Basic / },
              body: hash_including("grant_type" => "authorization_code", "code" => "CODE", "code_verifier" => "VERIFIER"))
        .to_return(status: 200, body: { access_token: "ACC", expires_in: 10 }.to_json)

      expect(auth.exchange_code_for_token(code: "CODE", verifier: "VERIFIER")["access_token"]).to eq("ACC")

      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .to_return(status: 200, body: { error: "invalid_request", error_description: "bad code" }.to_json)

      expect { auth.exchange_code_for_token(code: "BAD", verifier: "VERIFIER") }
        .to raise_error(Xbookmark::AuthError, /bad code/)

      stub_request(:post, "https://api.twitter.com/2/oauth2/token")
        .to_return(status: 400, body: "bad request")

      expect { auth.exchange_code_for_token(code: "DENIED", verifier: "VERIFIER") }
        .to raise_error(Xbookmark::AuthError, /Token exchange failed \(400\): bad request/)
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

  it "receives a matching OAuth callback code from the local server" do
    config = fake_config(env_path: "/tmp/.env")
    config.x_redirect_uri = "http://127.0.0.1:7799/callback"
    auth = described_class.new(config, opener: false, env_path: "/tmp/.env")
    server = fake_callback_server("state" => "ok", "code" => "CODE")
    allow(WEBrick::HTTPServer).to receive(:new).and_return(server)

    expect(auth.wait_for_callback(state: "ok", timeout: 5)).to eq("CODE")
    expect(server.response.status).to eq(200)
  end

  it "shuts down the callback server when the interrupt handler runs" do
    config = fake_config(env_path: "/tmp/.env")
    auth = described_class.new(config, opener: false, env_path: "/tmp/.env")
    server = fake_callback_server("state" => "ok", "code" => "CODE")
    allow(WEBrick::HTTPServer).to receive(:new).and_return(server)
    allow(Signal).to receive(:trap) do |_signal, previous = nil, &block|
      if block
        block.call
        "old-handler"
      else
        previous
      end
    end

    expect(capture_stderr { auth.wait_for_callback(state: "ok", timeout: 5) })
      .to include("auth login interrupted")
  end

  it "defaults to the keystore when no env file is loaded and resolves PATH lookups" do
    config = fake_config(env_path: nil)
    config.env_file = nil

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        auth = described_class.new(config, opener: false)
        expect(auth.instance_variable_get(:@env_path)).to be_nil
        expect(auth.send(:token_destination)).to eq("keystore: memory")

        tool = File.join(dir, "tool")
        File.write(tool, "#!/bin/sh\n")
        File.chmod(0o755, tool)
        stub_const("ENV", ENV.to_hash.merge("PATH" => dir))
        expect(auth.send(:which, "tool")).to eq(tool)

        stub_const("ENV", ENV.to_hash.merge("PATH" => "/no/such/dir"))
        expect(auth.send(:which, "missing")).to be_nil
      end
    end
  end

  it "falls back to the user env file when the automatic keystore is unavailable" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      config = fake_config(env_path: nil)
      config.env_file = nil
      allow(Xbookmark::Keystore).to receive(:default).and_raise(StandardError, "no backend")
      allow(Xbookmark::Paths).to receive(:user_env_path).and_return(env_path)

      auth = described_class.new(config, opener: false)
      auth.write_tokens!({ "access_token" => "ACC", "expires_in" => 10 })

      expect(auth.instance_variable_get(:@env_path)).to eq(env_path)
      expect(File.read(env_path)).to include("X_ACCESS_TOKEN=ACC")
    end
  end

  it "rejects mismatched state and missing callback code" do
    [
      ["wrong-state", "state=bad&code=CODE", "State mismatch"],
      ["missing-code", "state=ok", "Missing code"]
    ].each do |_case_name, query, body|
      config = fake_config(env_path: "/tmp/.env")
      config.x_redirect_uri = "http://127.0.0.1:7799/callback"
      auth = described_class.new(config, opener: false, env_path: "/tmp/.env")
      server = fake_callback_server(Hash[URI.decode_www_form(query)])
      allow(WEBrick::HTTPServer).to receive(:new).and_return(server)

      expect { auth.wait_for_callback(state: "ok", timeout: 5) }
        .to raise_error(Xbookmark::AuthError, /no code/)
      expect(server.response.body).to include(body)
    end
  end

  it "times out when the OAuth callback never arrives" do
    config = fake_config(env_path: "/tmp/.env")
    config.x_redirect_uri = "http://127.0.0.1:7799/callback"
    auth = described_class.new(config, opener: false, env_path: "/tmp/.env")
    server = fake_timeout_server
    allow(WEBrick::HTTPServer).to receive(:new).and_return(server)

    expect { auth.wait_for_callback(state: "ok", timeout: 0.01) }
      .to raise_error(Xbookmark::AuthError, /timed out/)
  end

  AuthFakeResponse = Struct.new(:status, :body, keyword_init: true)
  AuthFakeRequest = Struct.new(:query, keyword_init: true)

  def fake_callback_server(query)
    Class.new do
      attr_reader :response

      define_method(:initialize) do |callback_query|
        @query = callback_query
      end

      def mount_proc(_path, &block)
        @block = block
      end

      def start
        @response = AuthFakeResponse.new(status: 200, body: "")
        @block.call(AuthFakeRequest.new(query: @query), @response)
      end

      def shutdown; end
    end.new(query)
  end

  def fake_timeout_server
    Class.new do
      def mount_proc(_path, &_block); end

      def start
        sleep 0.01 until @shutdown
      end

      def shutdown
        @shutdown = true
      end
    end.new
  end

  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end
end
