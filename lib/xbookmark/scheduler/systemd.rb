# frozen_string_literal: true

require "fileutils"
require_relative "base"

module Xbookmark
  module Scheduler
    class Systemd < Base
      UNIT_DIR = File.join(Dir.home, ".config/systemd/user")
      SERVICE = "xbookmark-sync.service"
      TIMER   = "xbookmark-sync.timer"

      def install(time:, dry_run: false)
        hour, minute = parse_time(time)
        service = render_service
        timer = render_timer(hour, minute)
        log_dir = @config.logs_dir
        log_path = File.join(log_dir, "sync.log")

        if dry_run
          puts "# #{File.join(UNIT_DIR, SERVICE)}\n#{service}\n# #{File.join(UNIT_DIR, TIMER)}\n#{timer}"
          return
        end

        FileUtils.mkdir_p(UNIT_DIR)
        FileUtils.mkdir_p(log_dir)
        File.write(File.join(UNIT_DIR, SERVICE), service)
        File.write(File.join(UNIT_DIR, TIMER), timer)
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "enable", "--now", TIMER)
        warn "[xbookmark] systemd timer installed. Logs: #{log_path}"
        warn "[xbookmark] note: run `loginctl enable-linger $USER` to fire while logged out." unless lingering?
      end

      def uninstall(time: nil, dry_run: false)
        if dry_run
          puts "# would: systemctl --user disable --now #{TIMER}"
          puts "# would: rm #{File.join(UNIT_DIR, SERVICE)} #{File.join(UNIT_DIR, TIMER)}"
          return
        end
        run("systemctl", "--user", "disable", "--now", TIMER)
        File.delete(File.join(UNIT_DIR, SERVICE)) if File.exist?(File.join(UNIT_DIR, SERVICE))
        File.delete(File.join(UNIT_DIR, TIMER)) if File.exist?(File.join(UNIT_DIR, TIMER))
        run("systemctl", "--user", "daemon-reload")
      end

      def status
        out, = capture("systemctl", "--user", "status", TIMER)
        out
      end

      def render_service
        env_file = @config.env_file
        env_line = env_file ? "EnvironmentFile=#{env_file}" : ""
        log_file = File.join(@config.logs_dir, "sync.log")
        bin = xbookmark_bin
        <<~UNIT
          [Unit]
          Description=xbookmark sync — pull new X bookmarks into the local vault
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          #{env_line}
          ExecStart=#{bin} sync --from-scheduler
          StandardOutput=append:#{log_file}
          StandardError=append:#{log_file}
          Nice=10
          IOSchedulingClass=best-effort
          IOSchedulingPriority=5
        UNIT
      end

      def render_timer(hour, minute)
        <<~UNIT
          [Unit]
          Description=Run xbookmark-sync daily at #{format("%02d:%02d", hour, minute)}

          [Timer]
          OnCalendar=*-*-* #{format("%02d:%02d:00", hour, minute)}
          Persistent=true
          AccuracySec=1min
          Unit=#{SERVICE}

          [Install]
          WantedBy=timers.target
        UNIT
      end

      private

      def lingering?
        return @lingering if defined?(@lingering)
        out, = capture("loginctl", "show-user", ENV.fetch("USER", "user"), "--property=Linger")
        @lingering = out.to_s.include?("Linger=yes")
      rescue StandardError
        @lingering = false
      end

      def run(*argv)
        system(*argv)
      end

      def capture(*argv)
        require "open3"
        out, err, status = Open3.capture3(*argv)
        [out, err, status]
      end
    end
  end
end
