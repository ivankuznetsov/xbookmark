# frozen_string_literal: true

require "yaml"
require "digest"
require "json"
require "time"
require_relative "atomic_writer"
require_relative "wikilinks"
require_relative "bookmark_renderer"

module Xbookmark
  module Render
    class AuxPage
      KIND = nil # subclasses override

      def initialize(vault_path:, store:, orchestrator: nil)
        @vault_path = vault_path
        @store = store
        @orch = orchestrator
      end

      # Ensures the page exists. Inputs is an array of strings (text used
      # as the LLM input set); regenerate the summary only when its
      # canonical SHA256 differs from the stored digest.
      def ensure!(slug:, label:, inputs:)
        path = page_path(slug)
        digest = canonical_digest(inputs)
        existing = @store.find_page(self.class::KIND, slug)
        regenerate = existing.nil? || existing[:summary_input_digest] != digest

        summary = if regenerate && @orch && !inputs.empty?
                    generate_summary(slug: slug, label: label, inputs: inputs)
                  else
                    existing && File.exist?(path) ? extract_existing_summary(path) : nil
                  end

        content = render(slug: slug, label: label, summary: summary)
        AtomicWriter.write(path, content)
        @store.upsert_page(
          kind: self.class::KIND,
          slug: slug,
          path: relativize(path),
          summary_input_digest: digest,
          summarized_at: regenerate && summary ? Time.now.utc : nil
        )
        path
      end

      def page_path(slug)
        File.join(@vault_path, dir_name, "#{slug}.md")
      end

      def dir_name
        case self.class::KIND
        when "author" then "authors"
        when "topic"  then "topics"
        when "entity" then "entities"
        when "link"   then "links"
        when "thread" then "threads"
        end
      end

      def canonical_digest(inputs)
        canonical = inputs.sort.uniq
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      def generate_summary(slug:, label:, inputs:)
        # subclasses override
        nil
      end

      def render(slug:, label:, summary:)
        front = {
          "kind" => self.class::KIND,
          "slug" => slug,
          "label" => label,
          "xbookmark_schema" => SCHEMA_VERSION
        }
        front_yaml = front.to_yaml(line_width: -1).sub(/^---\n?/, "")
        body = "# #{label || slug}\n\n## Summary\n\n#{summary || "(no summary yet)"}\n\n## References\n\n_Use Obsidian's Backlinks panel to see every bookmark referencing this page._\n"
        "---\n#{front_yaml}---\n\n#{body}"
      end

      def relativize(path)
        prefix = @vault_path.to_s.sub(%r{/\z}, "")
        return path unless path.to_s.start_with?(prefix)
        path.to_s[(prefix.length + 1)..]
      end

      def extract_existing_summary(path)
        body = File.read(path)
        m = body.match(/## Summary\n\n(.+?)\n\n##/m)
        m ? m[1] : nil
      rescue StandardError
        nil
      end
    end

    class AuthorPage < AuxPage
      KIND = "author"

      def generate_summary(slug:, label:, inputs:)
        @orch.summarize_author(handle: slug, snippets: inputs.first(50))
      rescue StandardError
        nil
      end
    end

    class TopicPage < AuxPage
      KIND = "topic"

      def generate_summary(slug:, label:, inputs:)
        @orch.summarize_topic(slug: slug, snippets: inputs.first(50))
      rescue StandardError
        nil
      end
    end

    class EntityPage < AuxPage
      KIND = "entity"

      def generate_summary(slug:, label:, inputs:)
        @orch.summarize_topic(slug: slug, snippets: inputs.first(50))
      rescue StandardError
        nil
      end
    end

    class LinkPage < AuxPage
      KIND = "link"

      # For link pages we render the article extract directly (no LLM).
      def render(slug:, label:, summary:)
        front = {
          "kind" => "link",
          "slug" => slug,
          "label" => label,
          "xbookmark_schema" => SCHEMA_VERSION
        }
        front_yaml = front.to_yaml(line_width: -1).sub(/^---\n?/, "")
        body = "# #{label || slug}\n\n#{summary || "(no extract yet)"}\n"
        "---\n#{front_yaml}---\n\n#{body}"
      end
    end

    class ThreadPage < AuxPage
      KIND = "thread"
    end
  end
end
