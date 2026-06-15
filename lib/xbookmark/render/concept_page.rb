# frozen_string_literal: true

require "yaml"
require_relative "atomic_writer"
require_relative "bookmark_renderer"
require_relative "markdown_safety"
require_relative "wikilinks"

module Xbookmark
  module Render
    class ConceptPage
      def initialize(vault_path:, store: nil, references: nil)
        @vault_path = vault_path
        @store = store
        @references = references || {}
      end

      def ensure!(concept)
        path = page_path(concept.slug)
        content = render(concept)
        AtomicWriter.write(path, content)
        @store&.upsert_page(kind: "concept", slug: concept.slug, path: relativize(path))
        path
      end

      def page_path(slug)
        File.join(@vault_path, "concepts", "#{Wikilinks.slug(slug)}.md")
      end

      def render(concept)
        front = {
          "xbookmark_schema" => SCHEMA_VERSION,
          "kind" => "concept",
          "slug" => concept.slug,
          "label" => MarkdownSafety.frontmatter_string(concept.label),
          "concept_kind" => concept.kind,
          "aliases" => MarkdownSafety.alias_list(concept.aliases),
          "broader" => concept.broader,
          "tags" => MarkdownSafety.tags(concept.facets),
          "evidence_count" => concept.evidence_count,
          "confidence" => concept.confidence,
          "curator_outcome" => concept.outcome
        }
        broader = concept.broader.map { |slug| "- #{Wikilinks.link("concepts/#{slug}", label_for(slug))}" }
        posts = post_items(@references[concept.slug])
        body = ["# #{MarkdownSafety.wikilink_label(concept.label)}"]
        body << "## Broader\n\n#{broader.join("\n")}" unless broader.empty?
        body << "## Posts\n\n#{posts.join("\n")}" unless posts.empty?
        body << "## References\n\n_Use Obsidian's Backlinks panel to see source notes for this concept._"
        "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body.join("\n\n")}\n"
      end

      def self.references_by_concept(vault_path:, concepts: [])
        direct = direct_references(vault_path)
        return direct if Array(concepts).empty?

        broader = Array(concepts).to_h { |concept| [concept.slug, Array(concept.broader)] }
        inherited = Hash.new { |hash, key| hash[key] = [] }
        direct.each do |slug, references|
          inherited[slug].concat(references)
          ancestors_for(slug, broader).each { |ancestor| inherited[ancestor].concat(references) }
        end
        inherited.transform_values { |references| unique_references(references) }
      end

      def self.add_note_references!(references, path, vault_path:)
        note = reference_from_note(path, vault_path: vault_path)
        return references unless note

        note[:slugs].each do |slug|
          references[slug] ||= []
          references[slug] << note[:reference]
          references[slug] = unique_references(references[slug])
        end
        references
      end

      private

      def self.direct_references(vault_path)
        Dir.glob(File.join(vault_path, "bookmarks", "**", "*.md")).sort.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, references|
          add_note_references!(references, path, vault_path: vault_path)
        end.transform_values { |refs| unique_references(refs) }
      end

      def self.reference_from_note(path, vault_path:)
        front, body = parse_note(path)
        return nil unless front

        slugs = concept_slugs(front)
        return nil if slugs.empty?

        {
          slugs: slugs,
          reference: {
            target: relativize(path, vault_path).sub(/\.md\z/, ""),
            label: reference_label(front, body, path),
            author: front["author"].to_s.empty? ? nil : "@#{front["author"]}",
            bookmarked_at: front["bookmarked_at"].to_s
          }
        }
      end

      def self.concept_slugs(front)
        (Array(front["concepts"]) + Array(front["topics"]) + Array(front["entities"]))
          .map { |slug| Wikilinks.slug(slug) }
          .reject(&:empty?)
          .uniq
      end

      def self.reference_label(front, body, path)
        label = front["summary"].to_s
        label = body.to_s.lines.find { |line| line.start_with?("# ") }.to_s.delete_prefix("# ").strip if label.strip.empty?
        label = front["tweet_id"].to_s if label.strip.empty?
        label = File.basename(path, ".md") if label.strip.empty?
        truncate_label(label)
      end

      def self.parse_note(path)
        raw = File.read(path)
        return [{}, raw] unless raw.start_with?("---\n")

        _empty, yaml, body = raw.split("---\n", 3)
        front = YAML.safe_load(yaml, aliases: false)
        return [nil, raw] unless front.nil? || front.is_a?(Hash)

        [front || {}, body.to_s]
      rescue Psych::SyntaxError
        [nil, ""]
      end

      def self.ancestors_for(slug, broader, seen = [])
        return [] if seen.include?(slug)

        parents = Array(broader[slug])
        parents + parents.flat_map { |parent| ancestors_for(parent, broader, seen + [slug]) }
      end

      def self.unique_references(references)
        references
          .uniq { |reference| reference[:target] }
          .sort_by { |reference| [reference[:bookmarked_at].to_s, reference[:target].to_s] }
          .reverse
      end

      def self.relativize(path, vault_path)
        prefix = vault_path.to_s.sub(%r{/\z}, "")
        return path unless path.to_s.start_with?(prefix)

        path.to_s[(prefix.length + 1)..]
      end

      def self.truncate_label(value, max = 160)
        out = +""
        value.to_s.gsub(/\s+/, " ").strip.each_char do |char|
          break if out.length >= max

          out << char
        end
        out
      end

      def post_items(references)
        Array(references).map do |reference|
          meta = [reference[:author], reference[:bookmarked_at].to_s[0, 10]].compact.reject(&:empty?).join(", ")
          suffix = meta.empty? ? "" : " — #{meta}"
          "- #{Wikilinks.link(reference[:target], reference[:label])}#{suffix}"
        end
      end

      def label_for(slug)
        slug.to_s.split("-").map(&:capitalize).join(" ")
      end

      def relativize(path)
        prefix = @vault_path.to_s.sub(%r{/\z}, "")
        return path unless path.to_s.start_with?(prefix)

        path.to_s[(prefix.length + 1)..]
      end
    end
  end
end
