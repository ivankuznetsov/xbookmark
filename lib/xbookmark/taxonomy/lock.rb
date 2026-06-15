# frozen_string_literal: true

require "fileutils"

module Xbookmark
  module Taxonomy
    # Advisory cross-process lock guarding destructive taxonomy work. A sync
    # run and a manual `taxonomy rebuild --apply` both mutate the same
    # bookmarks/threads/concepts files, so they must never run concurrently.
    # The lock is a non-blocking flock on `.xbookmark/taxonomy.lock`; callers
    # that fail to acquire it should skip rather than race.
    module Lock
      LOCK_RELATIVE = File.join(".xbookmark", "taxonomy.lock")

      module_function

      # Returns an open, locked File on success, or nil when another holder
      # already owns the lock.
      def acquire(vault_path)
        lock_path = File.join(vault_path, LOCK_RELATIVE)
        FileUtils.mkdir_p(File.dirname(lock_path))
        file = File.open(lock_path, "w")
        return file if file.flock(File::LOCK_EX | File::LOCK_NB)

        file.close
        nil
      end

      def release(file)
        return unless file

        file.flock(File::LOCK_UN)
        file.close
      end

      def with_lock(vault_path)
        file = acquire(vault_path)
        raise "taxonomy maintenance already running" unless file

        begin
          yield
        ensure
          release(file)
        end
      end
    end
  end
end
