# frozen_string_literal: true

require_relative "../config"
require_relative "../x/client"
require_relative "../browser/source"

module Xbookmark
  module Sources
    # Builds the ordered list of bookmark sources the Sync::Runner should drive,
    # per config.source. Each source implements the same duck-typed contract:
    # `bookmarks(user_id:, max_results:) { |envelope| }` and `get_tweet(id)`.
    #
    # The order matters for `both`: the API source runs first, so a healthy API
    # token keeps syncing even when the browser session has expired.
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
