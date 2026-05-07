# frozen_string_literal: true

module Xbookmark
  module Scheduler
    class Base
      def initialize(config:)
        @config = config
      end

      def install(time:, dry_run: false); raise NotImplementedError; end
      def uninstall(time: nil, dry_run: false); raise NotImplementedError; end
      def status; raise NotImplementedError; end

      def xbookmark_bin
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          full = File.join(dir, "xbookmark")
          return full if File.executable?(full) && !File.directory?(full)
        end
        File.expand_path("../../../bin/xbookmark", __dir__)
      end

      def parse_time(time)
        m = time.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
        raise Xbookmark::Error, "invalid time #{time.inspect}, expected HH:MM" unless m
        hour = m[1].to_i
        minute = m[2].to_i
        unless (0..23).cover?(hour) && (0..59).cover?(minute)
          raise Xbookmark::Error, "invalid time #{time.inspect}, expected HH:MM with HH in 00-23 and MM in 00-59"
        end
        [hour, minute]
      end
    end
  end
end
