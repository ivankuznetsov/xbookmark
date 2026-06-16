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
  end
end
