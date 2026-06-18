# frozen_string_literal: true

require "fileutils"

require_relative "../../xbookmark"
require_relative "../paths"
require_relative "chromium"
require_relative "errors"

module Xbookmark
  module Browser
    # Owns the real-browser lifecycle for the browser bookmark source:
    # detects system Chromium, manages an isolated persistent profile, opens a
    # headed window for one-time login, and attaches headless for every later
    # run.
    #
    # Ferrum is reached only through `ferrum_browser_class` so tests inject a
    # fake browser and never launch real Chromium. The real `Ferrum::Browser`
    # spawn happens on exactly one line, behind that seam.
    class Session
      BOOKMARKS_URL = "https://x.com/i/bookmarks"

      # URL fragments X redirects to when the session is not authenticated.
      UNAUTHENTICATED_MARKERS = ["/login", "/i/flow", "/account/access"].freeze

      # True when a navigated URL is a login / checkpoint interstitial rather
      # than the page we asked for. Shared by the bookmarks probe and the
      # source's per-navigation guard. An empty/blank URL is deliberately NOT a
      # login redirect: "the page never navigated / CDP returned nothing" is a
      # transient condition, and treating it as expired would fire a spurious
      # re-login on a still-valid session. It still fails `authenticated_url?`, so
      # the logged_in? probe stays correctly negative.
      def self.login_redirect?(url)
        normalized = url.to_s
        UNAUTHENTICATED_MARKERS.any? { |marker| normalized.include?(marker) }
      end

      # Cheap, browser-free check that a session has ever been persisted: the
      # isolated profile dir exists and holds Chromium state. Used by `doctor`
      # and `auth status` so they never have to launch Chromium to report.
      def self.profile_saved?(dir = Xbookmark::Paths.browser_profile_dir)
        File.directory?(dir) && !Dir.empty?(dir)
      end

      # Re-asserts 0700 on the profile dir (and its parent config dir). The
      # profile holds the live X session cookies — strictly more powerful than the
      # OAuth token — so a profile restored/copied with looser permissions stays
      # world-traversable until the next launch. A chmod launches no browser, so
      # `doctor`/`auth status` can re-harden on the browser-free diagnostic path.
      # Returns true when it hardened an existing dir, false when none exists.
      def self.secure_profile_dir!(dir = Xbookmark::Paths.browser_profile_dir)
        return false unless File.directory?(dir)

        parent = File.dirname(dir)
        FileUtils.chmod(0o700, parent) if File.directory?(parent)
        FileUtils.chmod(0o700, dir)
        true
      end

      # Shared browser-free profile report for the diagnostics (`doctor`, `auth
      # status`). Returns [saved?, message]. When a profile exists it re-hardens
      # 0700, but degrades a chmod failure (a profile restored as root, or a
      # chmod-rejecting FS) to a warning instead of crashing the "always report"
      # diagnostic with a raw Errno — the launch path keeps the hard chmod via
      # #secure_profile_dir!. Single home for the policy so `auth` and `doctor`
      # cannot drift (e.g. one silently stops re-hardening).
      def self.describe_profile(dir = Xbookmark::Paths.browser_profile_dir)
        return [false, "not set up (run: xbookmark auth login --browser)"] unless profile_saved?(dir)

        begin
          secure_profile_dir!(dir)
        rescue SystemCallError => e
          warn "[xbookmark] could not re-harden the browser profile dir #{dir}: #{e.class}: #{e.message}"
        end
        [true, "profile saved but unverified (#{dir}); validity is confirmed at next sync"]
      end

      def initialize(config:, headless: true, browser_class: nil, chromium_path: nil)
        @config = config
        @headless = headless
        @browser_class = browser_class
        @chromium_path = chromium_path
        @profile_lock = nil
      end

      def profile_dir
        Xbookmark::Paths.browser_profile_dir
      end

      # Absolute path to the Chromium binary; raises a clear, actionable
      # ConfigError when none is installed (Chromium is never bundled).
      def chromium_path
        @chromium_path ||= Chromium.detect || raise_missing_chromium
      end

      # Starts (and memoizes) the browser. Idempotent.
      def start
        @browser ||= build_browser
      end

      # Closes the browser and releases the profile lock. Teardown is guarded: a
      # Ferrum error while tearing down an already-crashed Chromium must never
      # replace an already-classified SessionExpired/TransientError on the way
      # out (which would escape SOURCE_BLOCK_ERRORS and abort a multi-source run
      # instead of isolating the browser source). @browser is always cleared.
      def quit
        @browser&.quit
      rescue StandardError
        # Swallow teardown failures so they can't mask the real error.
      ensure
        @browser = nil
        release_profile_lock
      end

      # Opens a fresh page, yields it, and always closes it afterwards. The
      # browser itself stays alive for reuse until `quit`.
      def with_page
        page = start.create_page
        yield page
      ensure
        begin
          page&.close
        rescue StandardError
          # Same rationale as #quit: never let page teardown mask the real error.
        end
      end

      # Opens a persistent page at `url` and returns it (not closed) so a human
      # can interact with it during a headed login. The browser stays alive
      # until `quit`.
      def open_page(url)
        page = start.create_page
        page.go_to(url)
        page
      end

      # True when the dedicated profile still has a valid X session: navigating
      # to the bookmarks page must land on the bookmarks page, not a login or
      # checkpoint interstitial.
      def logged_in?
        with_page do |page|
          page.go_to(BOOKMARKS_URL)
          authenticated_url?(page.current_url)
        end
      end

      private

      def authenticated_url?(url)
        return false if self.class.login_redirect?(url)

        url.to_s.include?("/i/bookmarks")
      end

      def build_browser
        klass = @browser_class || self.class.ferrum_browser_class
        options = ferrum_options
        # Take a cross-process lock on the profile before launching: the only
        # other mutual exclusion is the vault taxonomy flock, which the
        # `auth login --browser` path never holds, so a scheduled headless sync
        # and an interactive re-login could otherwise launch two Chromium
        # processes against the same user-data-dir and corrupt the shared
        # cookie/leveldb store — the very X session being repaired.
        acquire_profile_lock!
        begin
          # Record the resolved Chromium path at launch. The unattended timer
          # launches whatever `chromium`-named binary is first on PATH under the
          # live-X-session profile, so logging the path makes a spoofed binary
          # observable after the fact.
          warn "[xbookmark] launching Chromium: #{options[:browser_path]}"
          klass.new(options)
        rescue StandardError
          release_profile_lock
          raise
        end
      end

      # Generous bounds so the unattended daily walk can never hang Chromium
      # indefinitely (the OS-level RuntimeMaxSec on the systemd unit is the outer
      # backstop; these cap individual CDP ops and the process launch).
      FERRUM_TIMEOUT_SECONDS = 60
      FERRUM_PROCESS_TIMEOUT_SECONDS = 30

      def ferrum_options
        prepare_profile_dir!
        {
          headless: @headless,
          browser_path: chromium_path,
          save_path: profile_dir,
          # incognito: false keeps the browser context on-disk so the X login
          # cookies persist into later headless runs — without it Ferrum defaults
          # to an off-the-record context and `auth login --browser` would succeed
          # but save no reusable session.
          incognito: false,
          timeout: FERRUM_TIMEOUT_SECONDS,
          process_timeout: FERRUM_PROCESS_TIMEOUT_SECONDS,
          browser_options: { "user-data-dir" => profile_dir }
        }
      end

      def prepare_profile_dir!
        FileUtils.mkdir_p(profile_dir, mode: 0o700)
        self.class.secure_profile_dir!(profile_dir)
      end

      # Sibling lock file next to the profile dir (not inside it — Chromium owns
      # that tree). Mirrors the Taxonomy::Lock pattern: a non-blocking flock,
      # callers that can't acquire it must not race.
      def profile_lock_path
        "#{profile_dir}.lock"
      end

      def acquire_profile_lock!
        FileUtils.mkdir_p(File.dirname(profile_lock_path))
        file = File.open(profile_lock_path, "w")
        if file.flock(File::LOCK_EX | File::LOCK_NB)
          @profile_lock = file
          return
        end

        file.close
        raise Xbookmark::TransientError,
              "another xbookmark browser session is already using the profile at #{profile_dir}; " \
              "skipping this launch so two Chromium processes cannot corrupt the shared session store"
      end

      def release_profile_lock
        return unless @profile_lock

        @profile_lock.flock(File::LOCK_UN)
        @profile_lock.close
      rescue StandardError
        # Releasing a lock on an already-torn-down fd must never mask the real error.
      ensure
        @profile_lock = nil
      end

      def raise_missing_chromium
        raise Xbookmark::Browser::ChromiumMissing,
              "No Chromium/Chrome found. The browser bookmark source needs a system browser " \
              "(it is never bundled). Install one, e.g. `sudo pacman -S chromium` or " \
              "`sudo apt-get install -y chromium`, then re-run."
      end

      # Indirection seam: touching the real constant requires the ferrum gem but
      # does NOT spawn Chromium. Tests stub/inject around `build_browser`, so the
      # only real-browser launch lives in `klass.new` above.
      def self.ferrum_browser_class
        require "ferrum"
        ::Ferrum::Browser
      end
    end
  end
end
