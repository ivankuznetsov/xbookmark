# frozen_string_literal: true

require_relative "systemd"
require_relative "launchd"
require_relative "../paths"

module Xbookmark
  module Scheduler
    module Factory
      module_function

      def build(config:)
        if Xbookmark::Paths.linux?
          Systemd.new(config: config)
        elsif Xbookmark::Paths.macos?
          Launchd.new(config: config)
        else
          raise Xbookmark::UnsupportedPlatform, "xbookmark only ships scheduler integration for Linux (systemd) and macOS (launchd)."
        end
      end
    end
  end
end
