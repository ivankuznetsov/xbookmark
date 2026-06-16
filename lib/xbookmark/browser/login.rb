# frozen_string_literal: true

require "time"

require_relative "../../xbookmark"
require_relative "session"

module Xbookmark
  module Browser
    # Drives the one-time headed login: shows a one-time ToS/account-risk
    # consent prompt (first browser-mode run only), opens a visible browser for
    # the user to log in, waits for the session to become authenticated, and
    # records consent so the unattended scheduler never blocks on it.
    class Login
      CONSENT_KEY = "browser_consent_at"
      LOGIN_TIMEOUT_SECONDS = 300
      POLL_INTERVAL_SECONDS = 2
      # Real wait between login polls; injectable so tests run instantly.
      DEFAULT_SLEEPER = ->(seconds) { sleep(seconds) }

      CONSENT_WARNING = <<~TEXT
        ⚠  Browser bookmark source — please read

        This logs into X in a real browser and reads your bookmarks through X's
        internal web endpoints, not the official developer API. Automating your
        own account this way may violate X's Terms of Service and carries a real
        risk of rate-limiting or account suspension. You accept that risk.

        A dedicated, isolated browser profile is used (never your everyday
        browser). Continue? [y/N]:
      TEXT

      def initialize(config:, store:, session: nil, input: $stdin, output: $stdout,
                     clock: Time, sleeper: DEFAULT_SLEEPER)
        @config = config
        @store = store
        @session = session
        @input = input
        @output = output
        @clock = clock
        @sleeper = sleeper
      end

      # Returns true on a confirmed login, false on declined consent or timeout.
      def call
        return false unless ensure_consent!

        say "Opening a browser window. Log in to X there — this continues automatically once you're in."
        session.open_page(Session::BOOKMARKS_URL)
        if wait_for_login
          say "Browser session saved to #{session.profile_dir}. You can close the window."
          true
        else
          say "Login not detected within #{LOGIN_TIMEOUT_SECONDS}s. Re-run `xbookmark auth login --browser`."
          false
        end
      ensure
        session.quit
      end

      private

      def ensure_consent!
        return true if @store.get_meta(CONSENT_KEY)

        @output.print(CONSENT_WARNING)
        answer = @input.gets.to_s.strip.downcase
        unless %w[y yes].include?(answer)
          say "Consent declined; browser login aborted."
          return false
        end

        @store.set_meta(CONSENT_KEY, @clock.now.utc.iso8601)
        true
      end

      def wait_for_login
        max_polls.times do
          return true if session.logged_in?

          @sleeper.call(POLL_INTERVAL_SECONDS)
        end
        false
      end

      def max_polls
        [(LOGIN_TIMEOUT_SECONDS / POLL_INTERVAL_SECONDS), 1].max
      end

      def session
        @session ||= Session.new(config: @config, headless: false)
      end

      def say(line)
        @output.puts(line)
      end
    end
  end
end
