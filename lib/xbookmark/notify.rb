# frozen_string_literal: true

require_relative "paths"

module Xbookmark
  # Best-effort desktop notifications. Used to make a browser-session expiry on
  # an unattended scheduled run visible to a human (the non-zero exit + log are
  # the reliable signal; this is the friendly nudge). Never raises.
  module Notify
    module_function

    # Returns true if a notification command was dispatched, false otherwise
    # (unknown platform, missing binary, timeout, or any failure — all swallowed).
    #
    # Named `deliver` rather than `send` so it does not shadow Object#send (a
    # one-arg call would otherwise silently fall through to Ruby's reflective
    # send instead of this method).
    def deliver(title, body)
      argv = command_for(title, body)
      return false unless argv

      invoke(argv)
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

    # Fire-and-forget: spawn the notifier and detach so the unattended run never
    # blocks on it (a stuck or absent D-Bus would otherwise hang the timer before
    # it can exit). The notification is best-effort, so a successful spawn counts
    # as dispatched.
    def invoke(argv)
      pid = Process.spawn(*argv, out: File::NULL, err: File::NULL)
      Process.detach(pid)
      true
    end

    def applescript_quote(value)
      # Escape backslashes BEFORE quotes so a value ending in a backslash cannot
      # break out of the AppleScript string literal. The block form sidesteps
      # gsub's own backslash handling in the replacement.
      escaped = value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }
      %("#{escaped}")
    end
  end
end
