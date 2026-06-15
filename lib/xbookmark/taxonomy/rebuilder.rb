# frozen_string_literal: true

require "fileutils"
require "json"
require "ostruct"
require "set"
require "time"
require "yaml"
require_relative "../render/concept_index"
require_relative "../render/concept_page"
require_relative "../render/path_builder"
require_relative "auditor"
require_relative "concept"
require_relative "graph_health_report"
require_relative "lock"
require_relative "manifest"
require_relative "path_safety"
require_relative "registry"
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
        return Report.new(state: "clean", counts: before) unless actionable?(before) || missing_concept_pages?

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

      def missing_concept_pages?
        concepts = Array(@store.concepts)
        return false if concepts.empty?

        concepts.any? do |row|
          !File.exist?(File.join(@config.vault_path, "concepts", "#{row[:slug]}.md"))
        end
      end

      def apply_changes(before)
        stamp = @clock.call.strftime("%Y%m%d%H%M%S")
        snapshot_path = snapshot!(stamp)
        manifest = Manifest.new(path: File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.manifest.json"))

        # Run file operations first, collecting the state mutations they imply.
        # The snapshot is backup/audit evidence for manual recovery; rebuilds
        # are forward-only so successful repairs remain visible if a later
        # operation fails and the report marks the run partial.
        path_updates = rename_numeric_bookmarks(manifest)
        thread_ids = numeric_thread_ids
        real_thread_ids = real_numeric_thread_ids(thread_ids)
        singleton_thread_ids = thread_ids - real_thread_ids
        thread_moves = move_numeric_threads(manifest, real_thread_ids)
        rewrite_thread_links(manifest, singleton_thread_ids, thread_moves)
        prune_numeric_threads(manifest, singleton_thread_ids)

        commit_state!(path_updates, singleton_thread_ids, thread_moves)
        materialize_concepts(manifest)

        after = Auditor.new(vault_path: @config.vault_path).metrics
        graph_path = File.join(@config.vault_path, ".xbookmark", "taxonomy-#{stamp}.graph-health.json")
        GraphHealthReport.new(before: before, after: after).write(graph_path)
        reindex_qmd(manifest)
        manifest.write(snapshot_path: snapshot_path, graph_health_path: graph_path)

        Report.new(state: "applied", counts: after, manifest_path: manifest.path,
                   graph_health_path: graph_path, snapshot_path: snapshot_path)
      rescue StandardError => e
        # Keep successful forward repairs in place and record the failure next
        # to the pre-apply snapshot. The snapshot is intentionally not restored
        # automatically because SQLite and file operations cannot be rolled
        # back as one atomic unit.
        manifest&.write(snapshot_path: snapshot_path)
        Report.new(state: "partial_failure", counts: before, manifest_path: manifest&.path,
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

      def real_numeric_thread_ids(thread_ids)
        wanted = thread_ids.to_set
        return [] if wanted.empty?

        counts = Hash.new(0)
        count_thread_references(wanted, counts)
        count_store_conversations(wanted, counts)
        thread_ids.select { |id| counts[id] >= 2 }
      end

      def count_thread_references(wanted, counts)
        @safety.allowed_markdown_files.each do |path|
          next if path.include?("/threads/")

          content = File.read(path)
          wanted.each do |id|
            counts[id] += 1 if content.include?("threads/#{id}")
          end
        end
      end

      def count_store_conversations(wanted, counts)
        Array(@store.bookmarks).each do |row|
          conversation = conversation_id_from_row(row)
          counts[conversation] += 1 if wanted.include?(conversation)
        end
      end

      def conversation_id_from_row(row)
        return nil if row[:payload_json].to_s.empty?

        payload = JSON.parse(row[:payload_json])
        data = Array(payload && payload["data"]).first || {}
        data["conversation_id"].to_s unless data["conversation_id"].to_s.empty?
      rescue JSON::ParserError
        nil
      end

      def move_numeric_threads(manifest, thread_ids)
        thread_ids.map do |id|
          old_path = File.join(@config.vault_path, "threads", "#{id}.md")
          new_slug = "thread-#{id}"
          new_path = File.join(@config.vault_path, "threads", "#{new_slug}.md")
          @safety.validate_write_path!(new_path)
          raise "rename collision: #{relativize(new_path)} already exists" if File.exist?(new_path)

          FileUtils.mv(old_path, new_path)
          rewrite_thread_page_frontmatter(new_path, slug: new_slug, label: "thread #{new_slug}")
          relative = relativize(new_path)
          manifest.add(:rename_thread, "old_path" => relativize(old_path), "new_path" => relative,
                                       "old_slug" => id, "new_slug" => new_slug)
          [id, new_slug, relative]
        end
      end

      def rewrite_thread_page_frontmatter(path, slug:, label:)
        front, body = parse_note(path)
        return unless front

        front["kind"] ||= "thread"
        front["slug"] = slug
        front["label"] = label
        File.write(path, "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body.to_s.sub(/\A\n+/, "")}")
      end

      # Rewrite references to legacy numeric thread pages in one pass over the
      # generated notes: singleton references are stripped, while real
      # multi-bookmark thread pages move to non-numeric names.
      def rewrite_thread_links(manifest, pruned_ids, thread_moves)
        return if pruned_ids.empty? && thread_moves.empty?

        moved = thread_moves.to_h { |old_slug, new_slug, _relative| [old_slug, new_slug] }
        @safety.allowed_markdown_files.each do |path|
          original = File.read(path)
          rewritten = rewrite_thread_references(original, pruned_ids: pruned_ids, moved: moved)
          next if rewritten == original

          File.write(path, rewritten)
          manifest.add(:link_rewrite, "path" => relativize(path), "reason" => "numeric_thread_targets")
        end
      end

      def rewrite_thread_references(content, pruned_ids:, moved:)
        text = strip_pruned_thread_references(content, pruned_ids)
        return text if moved.empty?

        pattern = moved.keys.map { |id| Regexp.escape(id) }.join("|")
        text
          .gsub(/\[\[threads\/(#{pattern})(?:\|[^\]]*)?\]\]/) do
            new_slug = moved.fetch(Regexp.last_match(1))
            "[[threads/#{new_slug}|thread #{new_slug}]]"
          end
          .gsub(/^thread: ["']?threads\/(#{pattern})["']?[ \t]*$/) do
            "thread: threads/#{moved.fetch(Regexp.last_match(1))}"
          end
      end

      def strip_pruned_thread_references(content, pruned_ids)
        return content if pruned_ids.empty?

        pattern = pruned_ids.map { |id| Regexp.escape(id) }.join("|")
        content
          .gsub(/\n\n## Thread\n\n\[\[threads\/(?:#{pattern})(?:\|[^\]]*)?\]\]/, "")
          .gsub(/^thread: ["']?threads\/(?:#{pattern})["']?[ \t]*$/, "thread:")
      end

      def prune_numeric_threads(manifest, pruned_ids)
        pruned_ids.each do |id|
          path = File.join(@config.vault_path, "threads", "#{id}.md")
          FileUtils.rm_f(path)
          manifest.add(:prune_thread, "path" => relativize(path), "reason" => "numeric_singleton_thread")
        end
      end

      # Apply the deferred SQLite mutations once every file op has succeeded.
      def commit_state!(path_updates, pruned_ids, thread_moves)
        @store.commit_taxonomy_rebuild!(path_updates: path_updates, pruned_ids: pruned_ids, thread_moves: thread_moves)
      end

      def materialize_concepts(manifest)
        concepts = concept_pages_from_store
        return if concepts.empty?

        page = Xbookmark::Render::ConceptPage.new(vault_path: @config.vault_path, store: @store)
        concepts.each { |concept| page.ensure!(concept) }
        conflicts = concepts.count { |concept| !concept.canonical? }
        index_path = Xbookmark::Render::ConceptIndex.new(vault_path: @config.vault_path).write(concepts, conflicts: conflicts)
        manifest.add(:concept_materialize, "count" => concepts.size, "index_path" => relativize(index_path))
      end

      def concept_pages_from_store
        concepts = Array(@store.concepts).map { |row| materialized_concept(Registry.concept_from_row(row)) }
        roots = concepts.filter_map { |concept| legacy_root_concept(concept.broader.first) if legacy_root?(concept) }
        (roots + concepts).uniq(&:slug).sort_by(&:slug)
      end

      def materialized_concept(concept)
        root = legacy_root_slug(concept.kind)
        return concept unless root && concept.broader.empty?

        Concept.new(slug: concept.slug, label: concept.label, kind: concept.kind, aliases: concept.aliases,
                    broader: [root], facets: concept.facets, evidence_count: concept.evidence_count,
                    confidence: concept.confidence, outcome: concept.outcome)
      end

      def legacy_root_slug(kind)
        case kind.to_s
        when "topic" then "topics"
        when "entity" then "entities"
        end
      end

      def legacy_root?(concept)
        %w[topics entities].include?(concept.broader.first)
      end

      def legacy_root_concept(slug)
        Concept.new(slug: slug, label: slug.capitalize, kind: "category", evidence_count: 0, confidence: 1.0)
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
