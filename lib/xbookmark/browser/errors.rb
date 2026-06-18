# frozen_string_literal: true

require_relative "../../xbookmark"

module Xbookmark
  module Browser
    # Raised when the dedicated browser session is no longer authenticated —
    # the cookies expired, X served a checkpoint/login interstitial, or the
    # profile was cleared. Subclasses Xbookmark::AuthError so the Sync::Runner's
    # existing `rescue Xbookmark::AuthError` treats it as a source block, while
    # still letting callers distinguish "needs interactive re-login" from a
    # generic API token block (see Sync::Runner#source_blocked).
    class SessionExpired < Xbookmark::AuthError; end

    # Raised when no system Chromium/Chrome is installed (Chromium is required but
    # never bundled). Subclasses Xbookmark::ConfigError so the Sync::Runner still
    # isolates it as a source block, while letting the CLI emit a precise
    # CHROMIUM_MISSING token distinct from any other ConfigError on the
    # browser-login path (e.g. an invalid XBOOKMARK_SOURCE parsed by load_offline).
    class ChromiumMissing < Xbookmark::ConfigError; end
  end
end
