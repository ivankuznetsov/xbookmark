# frozen_string_literal: true

require "fileutils"
require_relative "base"

module Xbookmark
  module Scheduler
    class Launchd < Base
      AGENT_DIR = File.join(Dir.home, "Library/LaunchAgents")
      LABEL = "io.xbookmark.sync"
      PLIST_NAME = "#{LABEL}.plist"

      def install(time:, dry_run: false)
        hour, minute = parse_time(time)
        plist = render_plist(hour, minute)
        if dry_run
          puts "# #{File.join(AGENT_DIR, PLIST_NAME)}\n#{plist}"
          return
        end
        FileUtils.mkdir_p(AGENT_DIR)
        FileUtils.mkdir_p(@config.logs_dir)
        path = File.join(AGENT_DIR, PLIST_NAME)
        File.write(path, plist)
        system("launchctl", "unload", path)
        system("launchctl", "load", "-w", path)
        warn "[xbookmark] launchd agent installed at #{path}"
      end

      def uninstall(time: nil, dry_run: false)
        path = File.join(AGENT_DIR, PLIST_NAME)
        if dry_run
          puts "# would: launchctl unload #{path}"
          puts "# would: rm #{path}"
          return
        end
        system("launchctl", "unload", path) if File.exist?(path)
        File.delete(path) if File.exist?(path)
      end

      def status
        out = `launchctl list | grep #{LABEL}`
        out
      end

      def render_plist(hour, minute)
        log = File.join(@config.logs_dir, "sync.log")
        bin = xbookmark_bin
        envs = (@config.env_file ? { "XBOOKMARK_ENV_FILE" => @config.env_file } : {})
        env_xml = envs.map { |k, v| "      <key>#{k}</key><string>#{v}</string>" }.join("\n")
        <<~PLIST
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key><string>#{LABEL}</string>
            <key>ProgramArguments</key>
            <array>
              <string>#{bin}</string>
              <string>sync</string>
              <string>--from-scheduler</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
              <key>Hour</key><integer>#{hour}</integer>
              <key>Minute</key><integer>#{minute}</integer>
            </dict>
            <key>RunAtLoad</key><false/>
            <key>StandardOutPath</key><string>#{log}</string>
            <key>StandardErrorPath</key><string>#{log}</string>
          #{envs.empty? ? "" : "  <key>EnvironmentVariables</key>\n  <dict>\n#{env_xml}\n  </dict>\n"}
          </dict>
          </plist>
        PLIST
      end
    end
  end
end
