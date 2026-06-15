# frozen_string_literal: true

require "fileutils"
require "json"
require "ostruct"
require "set"
require "time"
require "yaml"
require_relative "../render/aux_page"
require_relative "../render/concept_index"
require_relative "../render/concept_page"
require_relative "../render/path_builder"
require_relative "../sync/thread_index"
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
        return Report.new(state: "clean", counts: before) unless needs_rebuild?(before)

        locked ? apply_changes(before) : with_lock { apply_changes(before) }
      rescue StandardError => e
        Report.new(state: "partial_failure", counts: before || {}, skipped: ["#{e.class}: #{e.message}"])
      end

      private

      def dry_run(before)
        state = needs_rebuild?(before) ? "proposed_changes" : "clean"
        Report.new(state: state, counts: before)
      end

      def needs_rebuild?(counts)
        actionable?(counts) || missing_concept_pages? || placeholder_thread_pages? ||
          missing_post_lists? || legacy_taxonomy_surface? || stale_concept_pages?
      end

      def actionable?(counts)
        counts.values_at(*Auditor::ACTIONABLE_KEYS).any?(&:positive?)
      end

      def missing_concept_pages?
        concepts = concept_pages_from_store
        return false if concepts.empty?

        concepts.any? do |concept|
          !File.exist?(File.join(@config.vault_path, "concepts", "#{concept.slug}.md"))
        end
      end

      def placeholder_thread_pages?
        placeholder_thread_slugs.any? do |slug|
          conversation = slug.delete_prefix("thread-")
          !representative_thread_text(conversation).to_s.strip.empty?
        end
      end

      def missing_post_lists?
        post_references_by_slug.any? do |slug, references|
          next false if references.empty?

          post_list_paths_for(slug).any? do |path|
            File.exist?(path) && !File.read(path).include?("## Posts")
          end
        end
      end

      def legacy_taxonomy_surface?
        Dir.glob(File.join(@config.vault_path, "{topics,entities}", "*.md")).any? ||
          @safety.allowed_markdown_files.any? do |path|
            next false unless path.include?("/bookmarks/")

            content = File.read(path)
            content.include?("\ntopics:") || content.include?("\nentities:") ||
              content.include?("[[topics/") || content.include?("[[entities/")
          end
      end

      def stale_concept_pages?
        stale_concept_paths.any?
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
        thread_moves.concat(rename_placeholder_threads(manifest))
        rewrite_thread_links(manifest, singleton_thread_ids, thread_moves)
        rewrite_legacy_taxonomy_links(manifest)
        clear_reference_caches!
        prune_numeric_threads(manifest, singleton_thread_ids)

        commit_state!(path_updates, singleton_thread_ids, thread_moves)
        materialize_concepts(manifest)
        prune_legacy_aux_pages(manifest)

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
          new_slug, label = thread_name_for(id)
          new_path = File.join(@config.vault_path, "threads", "#{new_slug}.md")
          @safety.validate_write_path!(new_path)
          raise "rename collision: #{relativize(new_path)} already exists" if File.exist?(new_path)

          FileUtils.mv(old_path, new_path)
          rewrite_thread_page(new_path, slug: new_slug, label: label)
          relative = relativize(new_path)
          manifest.add(:rename_thread, "old_path" => relativize(old_path), "new_path" => relative,
                                       "old_slug" => id, "new_slug" => new_slug)
          [id, new_slug, relative, label]
        end
      end

      def rename_placeholder_threads(manifest)
        placeholder_thread_slugs.filter_map do |old_slug|
          conversation = old_slug.delete_prefix("thread-")
          next if representative_thread_text(conversation).to_s.strip.empty?

          new_slug, label = thread_name_for(conversation)
          next if new_slug == old_slug

          old_path = File.join(@config.vault_path, "threads", "#{old_slug}.md")
          new_path = File.join(@config.vault_path, "threads", "#{new_slug}.md")
          @safety.validate_write_path!(new_path)
          raise "rename collision: #{relativize(new_path)} already exists" if File.exist?(new_path)

          FileUtils.mv(old_path, new_path)
          rewrite_thread_page(new_path, slug: new_slug, label: label)
          relative = relativize(new_path)
          manifest.add(:rename_thread, "old_path" => relativize(old_path), "new_path" => relative,
                                       "old_slug" => old_slug, "new_slug" => new_slug,
                                       "reason" => "placeholder_thread_label")
          [old_slug, new_slug, relative, label]
        end
      end

      def placeholder_thread_slugs
        Dir.glob(File.join(@config.vault_path, "threads", "*.md")).sort.filter_map do |path|
          slug = File.basename(path, ".md")
          slug if slug.match?(/\Athread-\d+\z/)
        end
      end

      def thread_name_for(conversation)
        text = representative_thread_text(conversation)
        slug = Xbookmark::Sync::ThreadIndex.slug_for(conversation: conversation, text: text)
        label = Xbookmark::Sync::ThreadIndex.label_for(text: text, fallback_slug: slug)
        [slug, label]
      end

      def representative_thread_text(conversation)
        thread_texts[conversation.to_s]
      end

      def thread_texts
        @thread_texts ||= begin
          texts = thread_texts_from_store
          thread_texts_from_notes(texts)
          texts
        end
      end

      def thread_texts_from_store
        Array(@store.bookmarks).each_with_object({}) do |row, texts|
          begin
            payload = row[:payload_json].to_s.empty? ? nil : JSON.parse(row[:payload_json])
            data = Array(payload && payload["data"]).first || {}
            conversation = data["conversation_id"].to_s
            text = data["text"].to_s
            texts[conversation] ||= text if !conversation.empty? && !text.strip.empty?
          rescue JSON::ParserError
            next
          end
        end
      end

      def thread_texts_from_notes(texts)
        @safety.allowed_markdown_files.each do |path|
          next if path.include?("/threads/")

          front, body = parse_note(path)
          next unless front

          text = front["summary"].to_s
          text = body.to_s.lines.find { |line| line.start_with?("# ") }.to_s.delete_prefix("# ").strip if text.strip.empty?
          next if text.strip.empty?

          File.read(path).scan(%r{threads/thread-(\d+)}).flatten.each do |conversation|
            texts[conversation] ||= text
          end
        end
      end

      def rewrite_thread_page(path, slug:, label:)
        front, body = parse_note(path)
        return unless front

        front["kind"] ||= "thread"
        front["slug"] = slug
        front["label"] = label
        body = body.to_s.sub(/\A\n+/, "")
        body =
          if body.start_with?("# ")
            body.sub(/\A# .*/, "# #{label}")
          else
            "# #{label}\n\n#{body}"
          end
        File.write(path, "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body}")
      end

      # Rewrite references to legacy numeric thread pages in one pass over the
      # generated notes: singleton references are stripped, while real
      # multi-bookmark thread pages move to non-numeric names.
      def rewrite_thread_links(manifest, pruned_ids, thread_moves)
        return if pruned_ids.empty? && thread_moves.empty?

        moved = thread_moves.to_h do |old_slug, new_slug, _relative, label|
          [old_slug, { slug: new_slug, label: label || "thread #{new_slug}" }]
        end
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
            thread = moved.fetch(Regexp.last_match(1))
            "[[threads/#{thread[:slug]}|#{thread[:label]}]]"
          end
          .gsub(/^thread: ["']?threads\/(#{pattern})["']?[ \t]*$/) do
            "thread: threads/#{moved.fetch(Regexp.last_match(1))[:slug]}"
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
        unless concepts.empty?
          page = Xbookmark::Render::ConceptPage.new(vault_path: @config.vault_path, store: @store,
                                                    references: post_references_by_slug)
          concepts.each { |concept| page.ensure!(concept) }
          conflicts = concepts.count { |concept| !concept.canonical? }
          index_path = Xbookmark::Render::ConceptIndex.new(vault_path: @config.vault_path).write(concepts, conflicts: conflicts)
          manifest.add(:concept_materialize, "count" => concepts.size, "index_path" => relativize(index_path))
        end
        prune_stale_concept_pages(manifest)
      end

      def concept_pages_from_store
        @concept_pages_from_store ||= begin
          all_concepts_from_store.select { |concept| concept_referenced?(concept) }.sort_by(&:slug)
        end
      end

      def all_concepts_from_store
        @all_concepts_from_store ||= Array(@store.concepts).map { |row| materialized_concept(Registry.concept_from_row(row)) }.uniq(&:slug)
      end

      def concept_referenced?(concept)
        Array(post_references_by_slug[concept.slug]).any?
      end

      def rewrite_legacy_taxonomy_links(manifest)
        count = 0
        Dir.glob(File.join(@config.vault_path, "bookmarks", "**", "*.md")).sort.each do |path|
          front, body = parse_note(path)
          next unless front

          concepts = source_note_concepts(front)
          rewritten_body = rewrite_legacy_concept_sections(body, concepts)
          rewritten_front = rewrite_legacy_concept_frontmatter(front, concepts)
          next if rewritten_front == front && rewritten_body == body

          File.write(path, "---\n#{rewritten_front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{rewritten_body.to_s.sub(/\A\n+/, "")}")
          count += 1
        end
        manifest.add(:legacy_taxonomy_rewrite, "count" => count) if count.positive?
      end

      def source_note_concepts(front)
        author = Xbookmark::Render::Wikilinks.slug(front["author"])
        (Array(front["concepts"]) + Array(front["topics"]) + Array(front["entities"]))
          .map { |slug| Xbookmark::Render::Wikilinks.slug(slug) }
          .reject(&:empty?)
          .reject { |slug| !author.empty? && slug == author }
          .uniq
      end

      def rewrite_legacy_concept_frontmatter(front, concepts)
        rewritten = front.dup
        rewritten.delete("concepts")
        rewritten.delete("topics")
        rewritten.delete("entities")
        rewritten["concepts"] = concepts unless concepts.empty?
        rewritten
      end

      def rewrite_legacy_concept_sections(body, concepts)
        text = body.to_s
          .gsub(/\n\n## Topics\n\n.*?(?=\n\n## |\z)/m, "")
          .gsub(/\n\n## Entities\n\n.*?(?=\n\n## |\z)/m, "")
        section = concepts_section(concepts)
        text = text.gsub(/\n\n## Concepts\n\n.*?(?=\n\n## |\z)/m, "")
        return text if section.empty?

        insert_before_next_section(text, section)
      end

      def concepts_section(concepts)
        return "" if concepts.empty?

        items = concepts.map { |slug| "- #{Xbookmark::Render::Wikilinks.link("concepts/#{slug}", slug)}" }
        "## Concepts\n\n#{items.join("\n")}"
      end

      def insert_before_next_section(body, section)
        index = body.index(/\n\n## /, 1)
        return "#{body.rstrip}\n\n#{section}\n" unless index

        "#{body[0...index].rstrip}\n\n#{section}#{body[index..]}"
      end

      def prune_legacy_aux_pages(manifest)
        count = 0
        %w[topics entities].each do |dir|
          Dir.glob(File.join(@config.vault_path, dir, "*.md")).sort.each do |path|
            FileUtils.rm_f(path)
            count += 1
            manifest.add(:prune_legacy_aux, "path" => relativize(path))
          end
          FileUtils.rmdir(File.join(@config.vault_path, dir)) rescue nil
        end
        %w[topic entity].each do |kind|
          Array(@store.pages(kind)).each { |row| @store.delete_page!(kind: kind, slug: row[:slug]) }
        end
        count
      end

      def prune_stale_concept_pages(manifest)
        stale_concept_paths.each do |path|
          FileUtils.rm_f(path)
          @store.delete_page!(kind: "concept", slug: File.basename(path, ".md")) if @store
          manifest.add(:prune_concept, "path" => relativize(path), "reason" => "no_source_references")
        end
      end

      def post_references_by_slug
        @post_references_by_slug ||= Xbookmark::Render::ConceptPage.references_by_concept(
          vault_path: @config.vault_path,
          concepts: all_concepts_from_store
        )
      end

      def post_list_paths_for(slug)
        [
          File.join(@config.vault_path, "concepts", "#{slug}.md"),
          File.join(@config.vault_path, "topics", "#{slug}.md"),
          File.join(@config.vault_path, "entities", "#{slug}.md")
        ]
      end

      def stale_concept_paths
        desired = concept_pages_from_store.map(&:slug).to_set
        Dir.glob(File.join(@config.vault_path, "concepts", "*.md")).reject do |path|
          File.basename(path) == "index.md" || desired.include?(File.basename(path, ".md"))
        end
      end

      def clear_reference_caches!
        @post_references_by_slug = nil
        @concept_pages_from_store = nil
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
