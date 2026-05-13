# frozen_string_literal: true

require "securerandom"
require "digest"
require "base64"
require "uri"
require "webrick"
require "faraday"
require "faraday/retry"
require "json"

module Xbookmark
  module X
    class Auth
      AUTH_HOST  = "https://twitter.com"
      AUTH_PATH  = "/i/oauth2/authorize"
      TOKEN_URL  = "https://api.twitter.com/2/oauth2/token"
      SCOPES     = %w[tweet.read users.read bookmark.read offline.access].freeze
      LOCAL_PORT = 7799
      DEFAULT_CALLBACK_TIMEOUT = 600 # seconds — bound the OAuth callback wait

      AuthResult = Struct.new(:env_file, :access_token, :refresh_token, :expires_at, keyword_init: true)

      def initialize(config, opener: nil, env_path: nil)
        @config = config
        @opener = opener
        @env_path = env_path || resolve_env_path
      end

      def login
        verifier = SecureRandom.urlsafe_base64(64)
        challenge = pkce_challenge(verifier)
        state = SecureRandom.hex(16)

        url = build_authorize_url(state: state, challenge: challenge)
        warn "Opening browser to authorize xbookmark..."
        warn url
        try_open(url)

        code = wait_for_callback(state: state)
        token = exchange_code_for_token(code: code, verifier: verifier)
        write_tokens!(token)
        AuthResult.new(
          env_file: @env_path,
          access_token: token["access_token"],
          refresh_token: token["refresh_token"],
          expires_at: token_expires_at(token)
        )
      end

      # Refresh tokens using the saved refresh_token; persist rotated tokens.
      def refresh!
        raise AuthError, "Missing refresh token; run `xbookmark auth login` first." if @config.x_refresh_token.to_s.empty?

        body = {
          grant_type: "refresh_token",
          refresh_token: @config.x_refresh_token,
          client_id: @config.x_client_id
        }

        res = token_conn.post(TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          if @config.x_client_secret && !@config.x_client_secret.to_s.empty?
            req.headers["Authorization"] = basic_auth(@config.x_client_id, @config.x_client_secret)
          end
          req.body = URI.encode_www_form(body)
        end

        unless res.success?
          raise AuthError, "Token refresh failed (#{res.status}): #{res.body}"
        end

        token = JSON.parse(res.body)
        write_tokens!(token, preserve_refresh: token["refresh_token"].nil?)
        AuthResult.new(
          env_file: @env_path,
          access_token: token["access_token"],
          refresh_token: token["refresh_token"] || @config.x_refresh_token,
          expires_at: token_expires_at(token)
        )
      end

      def pkce_challenge(verifier)
        digest = Digest::SHA256.digest(verifier)
        Base64.urlsafe_encode64(digest, padding: false)
      end

      def build_authorize_url(state:, challenge:)
        params = {
          response_type: "code",
          client_id: @config.x_client_id,
          redirect_uri: @config.x_redirect_uri,
          scope: SCOPES.join(" "),
          state: state,
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        "#{AUTH_HOST}#{AUTH_PATH}?#{URI.encode_www_form(params)}"
      end

      def try_open(url)
        return if @opener == false
        if @opener
          @opener.call(url)
        elsif which("xdg-open")
          system("xdg-open", url, out: File::NULL, err: File::NULL)
        elsif which("open")
          system("open", url, out: File::NULL, err: File::NULL)
        end
      rescue StandardError
        # Headless / SSH — printed URL is the fallback.
      end

      def wait_for_callback(state:, timeout: DEFAULT_CALLBACK_TIMEOUT)
        port = URI(@config.x_redirect_uri).port || LOCAL_PORT
        host = URI(@config.x_redirect_uri).host || "127.0.0.1"
        captured = nil
        server = WEBrick::HTTPServer.new(
          Port: port,
          BindAddress: host,
          Logger: WEBrick::Log.new(File::NULL),
          AccessLog: []
        )
        server.mount_proc "/callback" do |req, res|
          q = req.query
          if q["state"] != state
            res.status = 400
            res.body = "State mismatch — refusing."
          elsif q["code"]
            captured = q["code"]
            res.body = "Authorization complete. You can close this tab."
          else
            res.status = 400
            res.body = "Missing code parameter."
          end
          server.shutdown
        end

        prev_int_handler = Signal.trap("INT") do
          warn "[xbookmark] auth login interrupted; shutting down callback server."
          server.shutdown
        end

        timed_out = false
        begin
          server_thread = Thread.new { server.start }
          if server_thread.join(timeout).nil?
            timed_out = true
            server.shutdown
            server_thread.join(5)
          end
        ensure
          Signal.trap("INT", prev_int_handler) if prev_int_handler
        end

        raise AuthError, "OAuth callback timed out after #{timeout}s — re-run `xbookmark auth login`." if timed_out
        raise AuthError, "OAuth flow returned no code." unless captured
        captured
      end

      def exchange_code_for_token(code:, verifier:)
        body = {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: @config.x_redirect_uri,
          client_id: @config.x_client_id,
          code_verifier: verifier
        }

        res = token_conn.post(TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          if @config.x_client_secret && !@config.x_client_secret.to_s.empty?
            req.headers["Authorization"] = basic_auth(@config.x_client_id, @config.x_client_secret)
          end
          req.body = URI.encode_www_form(body)
        end

        unless res.success?
          raise AuthError, "Token exchange failed (#{res.status}): #{res.body}"
        end

        body = JSON.parse(res.body)
        if body.is_a?(Hash) && body["error"] && (!body["access_token"] || body["access_token"].to_s.empty?)
          detail = body["error_description"] || body["error"]
          raise AuthError, "Token exchange returned error: #{detail}"
        end
        body
      end

      def write_tokens!(token, preserve_refresh: false)
        access  = token["access_token"]
        refresh = token["refresh_token"] || (preserve_refresh ? @config.x_refresh_token : nil)
        expires = token_expires_at(token).to_i

        updates = {
          "X_ACCESS_TOKEN" => access,
          "X_TOKEN_EXPIRES_AT" => expires.to_s
        }
        updates["X_REFRESH_TOKEN"] = refresh if refresh

        atomic_update_env(@env_path, updates)
      end

      private

      def basic_auth(user, pass)
        "Basic " + Base64.strict_encode64("#{user}:#{pass}")
      end

      def token_expires_at(token)
        Time.now.to_i + (token["expires_in"] || 0).to_i
      end

      def token_conn
        @token_conn ||= Faraday.new do |f|
          f.request :retry, max: 1, interval: 0.5,
                    retry_statuses: [429, 500, 502, 503, 504]
          f.adapter Faraday.default_adapter
        end
      end

      def resolve_env_path
        @config.env_file || ::File.join(Dir.pwd, ".env")
      end

      def atomic_update_env(path, updates)
        FileUtils.mkdir_p(File.dirname(path))
        existing = File.exist?(path) ? File.read(path).each_line.to_a : []
        keys = updates.keys
        out_lines = []
        seen = {}
        existing.each do |line|
          if (m = line.match(/^([A-Z0-9_]+)=/)) && updates.key?(m[1])
            out_lines << "#{m[1]}=#{updates[m[1]]}\n"
            seen[m[1]] = true
          else
            out_lines << line
          end
        end
        keys.each do |k|
          next if seen[k]
          out_lines << "\n" if out_lines.any? && !out_lines.last.end_with?("\n")
          out_lines << "#{k}=#{updates[k]}\n"
        end
        tmp = "#{path}.tmp.#{Process.pid}.#{rand(10_000)}"
        # Tighten permissions BEFORE writing secrets so OAuth tokens never
        # touch disk under the default 0644 umask.
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |f|
          f.write(out_lines.join)
        end
        File.rename(tmp, path)
        File.chmod(0o600, path)
      end

      def which(cmd)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          full = File.join(dir, cmd)
          return full if File.executable?(full) && !File.directory?(full)
        end
        nil
      end
    end
  end
end
