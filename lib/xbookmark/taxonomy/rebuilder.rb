# frozen_string_literal: true

require "fileutils"
require "ostruct"
require "time"
require "yaml"
require_relative "../render/path_builder"
require_relative "auditor"
require_relative "graph_health_report"
require_relative "lock"
require_relative "manifest"
require_relative "path_safety"
require_relative "report"

module Xbookmark
  module Taxonomy
    class Rebuilder
      SNAPSHOT_DIRS = %w[bookmarks authors concepts threads topics entities].freeze

      def initialize(config:, store:, registrar: nil, clock: -> { Time.now.utc })
        @config = config
        @store = store
        @registrar = registrar
        @clock = clock
        @safety = PathSafety.new(vault_path: config.vault_path)
      end

      # `locked: true` lets a caller that already holds the taxonomy lock
      # (e.g. Sync::Runner around a whole run) drive the rebuild without
      # re-acquiring the non-reentrant flock.
      def call(apply: false, locked: false)
        before = Auditor.new(vault_path: @config.vault_path).metrics
        return dry_run(before) unless apply
        return Report.new(state: "clean", counts: before) unless actionable?(before)

        locked ? apply_changes(before) : with_lock { apply_changes(before) }
      rescue StandardError => e
        Report.new(state: "partial_failure", counts: before || {}, skipped: ["#{e.class}: #{e.message}"])
      end

      private

      def dry_run(before)
        state = actionable?(before) ? "proposed_changes" : "clean"
        Report.new(state: state, counts: before)
      end

      def actionable?(counts)
        counts.values_at(*Auditor::ACTIONABLE_KEYS).any?(&:positive?)
      end

      def apply_changes(before)
        stamp = @clock.call.strftime("%Y%m%d%H%M%S")
        snapshot_path = snapshot!(stamp)
        manifest = Manifest.new(path: File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.manifest.json"))

        # Run every destructive *file* operation first, collecting the state
        # mutations they imply. The SQLite writes are applied only after all
        # file ops succeed, so a mid-apply failure rolls back to the snapshot
        # with the DB untouched — files and state never diverge.
        path_updates = rename_numeric_bookmarks(manifest)
        pruned_ids = numeric_thread_ids
        rewrite_thread_links(manifest, pruned_ids)
        prune_numeric_threads(manifest, pruned_ids)

        commit_state!(path_updates, pruned_ids)

        after = Auditor.new(vault_path: @config.vault_path).metrics
        graph_path = File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.graph-health.json")
        GraphHealthReport.new(before: before, after: after).write(graph_path)
        reindex_qmd(manifest)
        manifest.write(snapshot_path: snapshot_path, graph_health_path: graph_path)

        Report.new(state: "applied", counts: after, manifest_path: manifest.path,
                   graph_health_path: graph_path, snapshot_path: snapshot_path)
      rescue StandardError => e
        # Roll the wiki back to the pre-apply snapshot and record what completed
        # before the failure. State writes are deferred to commit_state!, so the
        # files and SQLite never diverge on a partial apply.
        restore_snapshot!(snapshot_path)
        manifest.write(snapshot_path: snapshot_path)
        Report.new(state: "partial_failure", counts: before, manifest_path: manifest.path,
                   snapshot_path: snapshot_path, skipped: ["#{e.class}: #{e.message}"])
      end

      def rename_numeric_bookmarks(manifest)
        builder = Xbookmark::Render::PathBuilder.new(vault_path: @config.vault_path)
        path_updates = []
        taken = []
        Dir.glob(File.join(@config.vault_path, "bookmarks", "**", "*.md")).sort.each do |path|
          next unless File.basename(path, ".md").match?(/\A\d+\z/)

          front, body = parse_note(path)
          next unless front # malformed frontmatter — skip rather than rename on guessed data

          tweet_id = front["tweet_id"] || File.basename(path, ".md")
          bookmark = OpenStruct.new(
            tweet_id: tweet_id,
            author_handle: front["author"],
            text: front["summary"] || body.lines.first.to_s,
            bookmarked_at: front["bookmarked_at"] || front["created_at"] || @clock.call.iso8601,
            created_at: front["created_at"] || @clock.call.iso8601
          )
          target = builder.path_for(bookmark, taken_paths: taken)
          next if File.expand_path(path) == File.expand_path(target)

          @safety.validate_write_path!(target)
          raise "rename collision: #{relativize(target)} already exists" if File.exist?(target)

          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.mv(path, target)
          taken << target
          relative = relativize(target)
          path_updates << [tweet_id.to_s, relative]
          manifest.add(:rename, "old_path" => relativize(path), "new_path" => relative, "tweet_id" => tweet_id.to_s)
        end
        path_updates
      end

      def numeric_thread_ids
        Dir.glob(File.join(@config.vault_path, "threads", "*.md")).sort.filter_map do |path|
          id = File.basename(path, ".md")
          id if id.match?(/\A\d+\z/)
        end
      end

      # Strip references to soon-to-be-pruned numeric thread pages from every
      # generated note BEFORE the pages are deleted, so the rebuild never
      # leaves dangling `[[threads/<id>]]` wikilinks behind.
      def rewrite_thread_links(manifest, pruned_ids)
        return if pruned_ids.empty?

        @safety.allowed_markdown_files.each do |path|
          original = File.read(path)
          rewritten = strip_thread_references(original, pruned_ids)
          next if rewritten == original

          File.write(path, rewritten)
          manifest.add(:link_rewrite, "path" => relativize(path), "reason" => "pruned_numeric_thread")
        end
      end

      def strip_thread_references(content, pruned_ids)
        pruned_ids.reduce(content) do |text, id|
          quoted = Regexp.escape(id)
          text
            .gsub(/\n\n## Thread\n\n\[\[threads\/#{quoted}(?:\|[^\]]*)?\]\]/, "")
            .gsub(/^thread: ["']?threads\/#{quoted}["']?[ \t]*$/, "thread:")
        end
      end

      def prune_numeric_threads(manifest, pruned_ids)
        pruned_ids.each do |id|
          path = File.join(@config.vault_path, "threads", "#{id}.md")
          FileUtils.rm_f(path)
          manifest.add(:prune_thread, "path" => relativize(path), "reason" => "numeric_singleton_thread")
        end
      end

      # Apply the deferred SQLite mutations once every file op has succeeded.
      def commit_state!(path_updates, pruned_ids)
        path_updates.each { |tweet_id, relative| @store.update_bookmark_path!(tweet_id: tweet_id, markdown_path: relative) }
        pruned_ids.each { |id| @store.delete_page!(kind: "thread", slug: id) }
      end

      def snapshot!(stamp)
        root = File.join(@config.vault_path, ".xbookmark", "snapshots", "taxonomy-#{stamp}")
        FileUtils.mkdir_p(root)
        SNAPSHOT_DIRS.each do |dir|
          source = File.join(@config.vault_path, dir)
          FileUtils.cp_r(source, File.join(root, dir)) if File.directory?(source)
        end
        root
      end

      def restore_snapshot!(snapshot_path)
        return unless snapshot_path && File.directory?(snapshot_path)

        SNAPSHOT_DIRS.each do |dir|
          backup = File.join(snapshot_path, dir)
          target = File.join(@config.vault_path, dir)
          next unless File.directory?(backup)

          FileUtils.rm_rf(target)
          FileUtils.cp_r(backup, target)
        end
      end

      def with_lock(&block)
        Lock.with_lock(@config.vault_path, &block)
      end

      # Returns [front, body]. `front` is nil when the note has a frontmatter
      # block that does not parse — the caller skips those rather than
      # renaming them onto guessed metadata. A note with no frontmatter at all
      # is legitimately empty-front ({}).
      def parse_note(path)
        raw = File.read(path)
        return [{}, raw] unless raw.start_with?("---\n")

        _empty, yaml, body = raw.split("---\n", 3)
        front = YAML.safe_load(yaml, aliases: false)
        return [nil, raw] unless front.nil? || front.is_a?(Hash)

        [front || {}, body.to_s]
      rescue Psych::SyntaxError
        [nil, raw]
      end

      def reindex_qmd(manifest)
        return unless @registrar

        @registrar.ensure_registered! if @registrar.respond_to?(:ensure_registered!)
        status = @registrar.index!
        manifest.add(:qmd_reindex, "collection" => "bookmarks", "status" => status == :failed ? "failed" : "indexed")
      rescue StandardError => e
        # A search-index failure leaves stale search but does not corrupt the
        # wiki, so record it as a visible manifest entry instead of rolling
        # back the whole apply.
        manifest.add(:qmd_reindex, "collection" => "bookmarks", "status" => "failed", "error" => e.message)
      end

      def relativize(path)
        path.to_s.delete_prefix("#{@config.vault_path.to_s.sub(%r{/\z}, "")}/")
      end
    end
  end
end
