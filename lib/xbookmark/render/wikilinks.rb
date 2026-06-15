# frozen_string_literal: true

module Xbookmark
  module Render
    module Wikilinks
      module_function

      # Deterministic kebab-case slug for topics, entities, etc.
      def slug(label)
        return "" if label.nil?
        s = label.to_s.unicode_normalize(:nfkc).downcase
        s = s.gsub(/[^a-z0-9]+/, "-")
        s = s.gsub(/-+/, "-").gsub(/\A-|-\z/, "")
        s.empty? ? "untitled" : s
      end

      def topic_slug(label)
        slug(label)
      end

      def entity_slug(label)
        slug(label)
      end

      def author_slug(handle)
        return "" if handle.nil?
        handle.to_s.downcase.gsub(/\A@/, "").gsub(/[^a-z0-9_]/, "")
      end

      def link_slug(url)
        s = url.to_s
        s = s.sub(%r{\Ahttps?://}, "")
        slug(s)
      end

      def link(target, label = nil)
        if label && label != target
          "[[#{safe_link_part(target)}|#{safe_label(label)}]]"
        else
          "[[#{safe_link_part(target)}]]"
        end
      end

      def safe_label(value)
        value.to_s.gsub(/\]\]|\||\[\[/, " ").gsub(/\s+/, " ").strip
      end

      def safe_link_part(value)
        value.to_s.gsub(/\]\]|\[\[/, "").gsub(/\s+/, " ").strip
      end
    end
  end
end
