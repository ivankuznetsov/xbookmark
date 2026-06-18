# frozen_string_literal: true

require_relative "../paths"

module Xbookmark
  module Browser
    # Detects a system-installed Chromium/Chrome. Chromium is *required but not
    # bundled* (the Tebako binary ships no browser); this is the single place
    # that knows how to find one, so `doctor` and `Session` share one answer.
    module Chromium
      # Probed in order; the first executable on PATH wins.
      CANDIDATES = %w[
        chromium
        chromium-browser
        google-chrome
        google-chrome-stable
        chrome
      ].freeze

      # macOS installs land in /Applications rather than on PATH.
      MACOS_APP_PATHS = [
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      ].freeze

      module_function

      # Returns the absolute path to a Chromium/Chrome binary, or nil if none
      # is installed.
      def detect
        CANDIDATES.each do |cmd|
          path = which(cmd)
          return path if path
        end
        MACOS_APP_PATHS.each do |path|
          return path if File.executable?(path) && !File.directory?(path)
        end
        nil
      end

      # Delegates to the shared PATH scan; kept as a module method so callers (and
      # tests) that ask Chromium to resolve a binary still have a single answer.
      def which(cmd)
        Xbookmark::Paths.which(cmd)
      end
    end
  end
end
