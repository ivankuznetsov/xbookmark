# frozen_string_literal: true

require_relative "paths"

module Xbookmark
  # Best-effort desktop notifications. Used to make a browser-session expiry on
  # an unattended scheduled run visible to a human (the non-zero exit + log are
  # the reliable signal; this is the friendly nudge). Never raises.
  module Notify
    module_function

    # Returns true if a notification command was dispatched, false otherwise
    # (unknown platform, missing binary, or any failure — all swallowed).
    def send(title, body)
      argv = command_for(title, body)
      return false unless argv

      invoke(argv)
      true
    rescue StandardError
      false
    end

    def command_for(title, body)
      if Paths.macos?
        script = "display notification #{applescript_quote(body)} with title #{applescript_quote(title)}"
        ["osascript", "-e", script]
      elsif Paths.linux?
        ["notify-send", title.to_s, body.to_s]
      end
    end

    def invoke(argv)
      system(*argv, out: File::NULL, err: File::NULL)
    end

    def applescript_quote(value)
      %("#{value.to_s.gsub('"', '\\"')}")
    end
  end
end
