# frozen_string_literal: true

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
