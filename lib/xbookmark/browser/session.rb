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

      def initialize(config:, headless: true, browser_class: nil, chromium_path: nil)
        @config = config
        @headless = headless
        @browser_class = browser_class
        @chromium_path = chromium_path
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

      # Closes the browser and releases the profile lock.
      def quit
        @browser&.quit
        @browser = nil
      end

      # Opens a fresh page, yields it, and always closes it afterwards. The
      # browser itself stays alive for reuse until `quit`.
      def with_page
        page = start.create_page
        yield page
      ensure
        page&.close
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
        normalized = url.to_s
        return false if normalized.empty?
        return false if UNAUTHENTICATED_MARKERS.any? { |marker| normalized.include?(marker) }

        normalized.include?("/i/bookmarks")
      end

      def build_browser
        klass = @browser_class || self.class.ferrum_browser_class
        klass.new(ferrum_options)
      end

      def ferrum_options
        FileUtils.mkdir_p(profile_dir)
        {
          headless: @headless,
          browser_path: chromium_path,
          save_path: profile_dir,
          browser_options: { "user-data-dir" => profile_dir }
        }
      end

      def raise_missing_chromium
        raise Xbookmark::ConfigError,
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
