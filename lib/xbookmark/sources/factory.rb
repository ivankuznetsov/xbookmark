# frozen_string_literal: true

require_relative "../config"
require_relative "../x/client"
require_relative "../browser/source"

module Xbookmark
  module Sources
    # Builds the ordered list of bookmark sources the Sync::Runner should drive,
    # per config.source. The order matters for `both`: the API source runs
    # first, so a healthy API token keeps syncing even when the browser session
    # has expired.
    #
    # Source contract (the authoritative duck-typed interface every source must
    # satisfy; X::Client is the reference implementation):
    #
    #   bookmarks(user_id:, pagination_token: nil, max_results:) { |envelope| }
    #     Yields API v2 page envelopes. `pagination_token` is accepted for
    #     signature parity even by sources that drive their own cursor (the
    #     browser source accepts and ignores it). Returns an Enumerator with no
    #     block. Raises AuthError / RateLimited / TransientError to signal a
    #     source block.
    #
    #   get_tweet(id) -> { "data" => tweet, "includes" => {...} }
    #     Returns a single-tweet API v2 payload. Raises SourceUnavailable when
    #     the tweet is permanently gone and TransientError when the fetch failed
    #     transiently — it never returns nil, so the Runner can tell "retry" from
    #     "permanently gone".
    #
    #   close (optional)
    #     Releases any held resources (the browser source quits Chromium). The
    #     Runner calls it once per source after a run.
    module Factory
      module_function

      def build(config:, store:)
        case config.source
        when Xbookmark::Config::SOURCE_BROWSER
          [browser_source(config)]
        when Xbookmark::Config::SOURCE_BOTH
          [api_source(config, store), browser_source(config)]
        else
          [api_source(config, store)]
        end
      end

      def api_source(config, store)
        Xbookmark::X::Client.new(config: config, store: store)
      end

      def browser_source(config)
        Xbookmark::Browser::Source.new(config: config)
      end
    end
  end
end
