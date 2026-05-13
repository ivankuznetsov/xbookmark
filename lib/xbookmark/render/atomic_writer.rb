# frozen_string_literal: true

require "fileutils"

module Xbookmark
  module Render
    module AtomicWriter
      module_function

      # Writes content to path atomically. Creates parent directories. If
      # the block raises, no file is left at the destination and the .tmp
      # file is removed.
      def write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp.#{Process.pid}.#{rand(1_000_000)}"
        begin
          File.binwrite(tmp, content)
          File.rename(tmp, path)
        ensure
          File.delete(tmp) if File.exist?(tmp) && tmp != path
        end
      end

      # Atomically rename a directory into place. Both source and target
      # must be on the same filesystem.
      def rename_dir(src, dst)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.rm_rf(dst) if File.exist?(dst)
        File.rename(src, dst)
      end
    end
  end
end
