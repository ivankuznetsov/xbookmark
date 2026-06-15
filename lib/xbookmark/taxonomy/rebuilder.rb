# frozen_string_literal: true

require "fileutils"
require "ostruct"
require "time"
require "yaml"
require_relative "../render/path_builder"
require_relative "auditor"
require_relative "graph_health_report"
require_relative "manifest"
require_relative "path_safety"
require_relative "report"

module Xbookmark
  module Taxonomy
    class Rebuilder
      def initialize(config:, store:, registrar: nil, clock: -> { Time.now.utc })
        @config = config
        @store = store
        @registrar = registrar
        @clock = clock
        @safety = PathSafety.new(vault_path: config.vault_path)
      end

      def call(apply: false)
        before = Auditor.new(vault_path: @config.vault_path).metrics
        return dry_run(before) unless apply
        return Report.new(state: "clean", counts: before) unless actionable?(before)

        with_lock { apply_changes(before) }
      rescue StandardError => e
        Report.new(state: "partial_failure", counts: before || {}, skipped: [e.message])
      end

      private

      def dry_run(before)
        state = actionable?(before) ? "proposed_changes" : "clean"
        Report.new(state: state, counts: before)
      end

      def actionable?(counts)
        counts.values_at(:numeric_bookmark_nodes, :singleton_thread_pages, :one_off_compound_topics, :duplicate_alias_clusters).any?(&:positive?)
      end

      def apply_changes(before)
        stamp = @clock.call.strftime("%Y%m%d%H%M%S")
        snapshot_path = snapshot!(stamp)
        manifest = Manifest.new(path: File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.manifest.json"))

        rename_numeric_bookmarks(manifest)
        prune_numeric_threads(manifest)

        after = Auditor.new(vault_path: @config.vault_path).metrics
        graph_path = File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.graph-health.json")
        GraphHealthReport.new(before: before, after: after).write(graph_path)
        reindex_qmd(manifest)
        manifest.write(snapshot_path: snapshot_path, graph_health_path: graph_path)

        Report.new(state: "applied", counts: after, manifest_path: manifest.path, graph_health_path: graph_path)
      end

      def rename_numeric_bookmarks(manifest)
        builder = Xbookmark::Render::PathBuilder.new(vault_path: @config.vault_path)
        Dir.glob(File.join(@config.vault_path, "bookmarks", "**", "*.md")).sort.each do |path|
          next unless File.basename(path, ".md").match?(/\A\d+\z/)

          front, body = parse_note(path)
          tweet_id = front["tweet_id"] || File.basename(path, ".md")
          bookmark = OpenStruct.new(
            tweet_id: tweet_id,
            author_handle: front["author"],
            text: front["summary"] || body.lines.first.to_s,
            bookmarked_at: front["bookmarked_at"] || front["created_at"] || @clock.call.iso8601,
            created_at: front["created_at"] || @clock.call.iso8601
          )
          target = builder.path_for(bookmark)
          next if File.expand_path(path) == File.expand_path(target)

          @safety.validate_write_path!(target)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.mv(path, target)
          relative = relativize(target)
          @store.update_bookmark_path!(tweet_id: tweet_id, markdown_path: relative)
          manifest.add(:rename, "old_path" => relativize(path), "new_path" => relative, "tweet_id" => tweet_id.to_s)
        end
      end

      def prune_numeric_threads(manifest)
        Dir.glob(File.join(@config.vault_path, "threads", "*.md")).sort.each do |path|
          next unless File.basename(path, ".md").match?(/\A\d+\z/)

          FileUtils.rm_f(path)
          manifest.add(:prune_thread, "path" => relativize(path), "reason" => "numeric_singleton_thread")
        end
      end

      def snapshot!(stamp)
        root = File.join(@config.vault_path, ".xbookmark", "snapshots", "taxonomy-#{stamp}")
        FileUtils.mkdir_p(root)
        %w[bookmarks authors concepts threads topics entities].each do |dir|
          source = File.join(@config.vault_path, dir)
          FileUtils.cp_r(source, File.join(root, dir)) if File.directory?(source)
        end
        root
      end

      def with_lock
        lock_path = File.join(@config.vault_path, ".xbookmark", "taxonomy.lock")
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, "w") do |file|
          raise "taxonomy maintenance already running" unless file.flock(File::LOCK_EX | File::LOCK_NB)

          yield
        ensure
          file.flock(File::LOCK_UN) if file
        end
      end

      def parse_note(path)
        raw = File.read(path)
        return [{}, raw] unless raw.start_with?("---\n")

        _empty, yaml, body = raw.split("---\n", 3)
        [YAML.safe_load(yaml, aliases: false) || {}, body.to_s]
      rescue Psych::SyntaxError
        [{}, File.read(path)]
      end

      def reindex_qmd(manifest)
        return unless @registrar

        @registrar.ensure_registered! if @registrar.respond_to?(:ensure_registered!)
        @registrar.index!
        manifest.add(:qmd_reindex, "collection" => "bookmarks")
      end

      def relativize(path)
        path.to_s.delete_prefix("#{@config.vault_path.to_s.sub(%r{/\z}, "")}/")
      end
    end
  end
end
