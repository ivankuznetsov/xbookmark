# frozen_string_literal: true

module Xbookmark
  module System
    module Runtime
      module_function

      def kind
        return :bundled if bundled?
        :system
      end

      def bundled?
        # Tebako bakes either of these markers into the resulting binary.
        return true if ENV["TEBAKO_PEARL"]
        return true if defined?(::Tebako)
        return true if RUBY_DESCRIPTION.to_s.downcase.include?("tebako")
        return true if RbConfig::CONFIG["host_os"].to_s.match?(/tebako/i)
        false
      end

      def ruby_version
        RUBY_VERSION
      end

      def describe
        case kind
        when :bundled
          "bundled (tebako, ruby #{ruby_version})"
        else
          "system (ruby #{ruby_version})"
        end
      end
    end
  end
end
