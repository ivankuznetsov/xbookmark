# frozen_string_literal: true

require "fileutils"
require_relative "base"

module Xbookmark
  module Scheduler
    class Systemd < Base
      SERVICE = "xbookmark-sync.service"
      TIMER   = "xbookmark-sync.timer"
      # Hard wall-clock cap on a single scheduled run (2h) so a wedged run can
      # never sit resident until the next timer fires.
      RUNTIME_MAX_SECONDS = 7200

      # Compute lazily — capturing Dir.home at load time would lock in the
      # original $HOME and ignore subsequent test setup that re-points it.
      def self.unit_dir
        File.join(Dir.home, ".config/systemd/user")
      end

      def install(time:, dry_run: false)
        hour, minute = parse_time(time)
        service = render_service
        timer = render_timer(hour, minute)
        log_dir = @config.logs_dir
        log_path = File.join(log_dir, "sync.log")

        if dry_run
          puts "# #{File.join(self.class.unit_dir, SERVICE)}\n#{service}\n# #{File.join(self.class.unit_dir, TIMER)}\n#{timer}"
          return
        end

        FileUtils.mkdir_p(self.class.unit_dir)
        FileUtils.mkdir_p(log_dir)
        File.write(File.join(self.class.unit_dir, SERVICE), service)
        File.write(File.join(self.class.unit_dir, TIMER), timer)
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "enable", "--now", TIMER)
        warn "[xbookmark] systemd timer installed. Logs: #{log_path}"
        ensure_lingering!
      end

      def uninstall(time: nil, dry_run: false)
        if dry_run
          puts "# would: systemctl --user disable --now #{TIMER}"
          puts "# would: rm #{File.join(self.class.unit_dir, SERVICE)} #{File.join(self.class.unit_dir, TIMER)}"
          return
        end
        run("systemctl", "--user", "disable", "--now", TIMER)
        File.delete(File.join(self.class.unit_dir, SERVICE)) if File.exist?(File.join(self.class.unit_dir, SERVICE))
        File.delete(File.join(self.class.unit_dir, TIMER)) if File.exist?(File.join(self.class.unit_dir, TIMER))
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
          Description=xbookmark sync — pull new X bookmarks into the local bookmark wiki
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          #{env_line}
          ExecStart=#{bin} sync --from-scheduler
          StandardOutput=append:#{log_file}
          StandardError=append:#{log_file}
          # Outer backstop: kill a run that hangs (e.g. a wedged headless
          # Chromium walk) so the daily timer can never get stuck running.
          RuntimeMaxSec=#{RUNTIME_MAX_SECONDS}
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

      def ensure_lingering!
        return if lingering?

        user = ENV.fetch("USER", "user")
        if run("loginctl", "enable-linger", user)
          @lingering = true
          warn "[xbookmark] systemd linger enabled; timer can run while logged out."
        else
          warn "[xbookmark] warning: could not enable systemd linger automatically. Run `loginctl enable-linger #{user}` to let the timer fire while logged out."
        end
      rescue StandardError
        warn "[xbookmark] warning: could not enable systemd linger automatically. Run `loginctl enable-linger #{ENV.fetch('USER', 'user')}` to let the timer fire while logged out."
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
