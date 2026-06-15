# frozen_string_literal: true

require_relative "wikilinks"

module Xbookmark
  module Render
    module MarkdownSafety
      MAX_STRING = 200

      module_function

      def text(value, max: MAX_STRING)
        clean = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          .delete("\u0000")
          .gsub(/\s+/, " ")
          .strip
        clean = clean[0, max].strip if clean.length > max
        clean
      end

      def wikilink_label(value)
        clean = text(value).gsub(/\]\]|\||\[\[/, " ").gsub(/\s+/, " ").strip
        clean.empty? ? "untitled" : clean
      end

      def frontmatter_string(value, max: MAX_STRING)
        clean = text(value, max: max).gsub(/\A---+\z/, "")
        clean.empty? ? nil : clean
      end

      def alias_list(values, max_items: 20, max: MAX_STRING)
        Array(values).filter_map { |value| frontmatter_string(value, max: max) }.uniq.first(max_items)
      end

      def tag(value)
        parts = value.to_s.split("/").map { |part| Wikilinks.slug(part) }.reject(&:empty?)
        parts = ["untitled"] if parts.empty?
        parts.join("/")
      end

      def tags(values, max_items: 20)
        Array(values).filter_map { |value| tag(value) }.uniq.first(max_items)
      end

      def prompt_field(value, max: MAX_STRING)
        text(value, max: max).gsub(/`+/, "'").gsub(/[{}\[\]\|\n\r]/, " ").gsub(/\s+/, " ").strip
      end
    end
  end
end
