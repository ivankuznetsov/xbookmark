# frozen_string_literal: true

require "json"
require "yaml"
require_relative "concept"
require_relative "../render/wikilinks"

module Xbookmark
  module Taxonomy
    class Registry
      attr_reader :concepts

      def initialize(concepts = [])
        @concepts = {}
        @aliases = {}
        concepts.each { |concept| add(concept) }
      end

      def self.from_vault(vault_path, store: nil)
        registry = new
        Dir.glob(File.join(vault_path, "concepts", "*.md")).sort.each do |path|
          registry.add(concept_from_page(path))
        end
        Array(store&.concepts).each { |row| registry.add(concept_from_row(row)) }
        registry
      end

      def self.concept_from_page(path)
        raw = File.read(path)
        front = raw.start_with?("---\n") ? YAML.safe_load(raw.split("---\n", 3)[1], permitted_classes: [Time], aliases: false) || {} : {}
        Concept.new(
          slug: front["slug"] || File.basename(path, ".md"),
          label: front["label"],
          kind: front["kind"],
          aliases: front["aliases"],
          broader: front["broader"],
          facets: front["tags"] || front["facets"],
          evidence_count: front["evidence_count"] || 1,
          confidence: front["confidence"],
          outcome: front["curator_outcome"] || front["outcome"]
        )
      end

      def self.concept_from_row(row)
        Concept.new(
          slug: row[:slug],
          label: row[:label],
          kind: row[:kind],
          aliases: json_array(row[:aliases_json]),
          broader: json_array(row[:broader_json]),
          facets: json_array(row[:facets_json]),
          evidence_count: row[:evidence_count],
          confidence: row[:confidence],
          outcome: row[:curator_outcome]
        )
      end

      def self.json_array(value)
        value.to_s.empty? ? [] : JSON.parse(value)
      rescue JSON::ParserError
        []
      end

      def add(concept)
        concept = Concept.new(**concept) if concept.is_a?(Hash)
        @concepts[concept.slug] = concept
        ([concept.slug, concept.label] + concept.aliases).each do |value|
          @aliases[Xbookmark::Render::Wikilinks.slug(value)] = concept.slug
        end
        concept
      end

      def find(value)
        @concepts[@aliases[Xbookmark::Render::Wikilinks.slug(value)]]
      end

      def include?(value)
        !find(value).nil?
      end

      def all
        @concepts.values.sort_by(&:slug)
      end

      def relevant(labels, limit: 20)
        wanted = Array(labels).flat_map { |label| Xbookmark::Render::Wikilinks.slug(label).split("-") }
        scored = all.map do |concept|
          haystack = ([concept.slug, concept.label] + concept.aliases + concept.broader).join(" ")
          [concept, wanted.count { |part| haystack.include?(part) }]
        end
        scored.select { |_concept, score| score.positive? }.sort_by { |concept, score| [-score, concept.slug] }.map(&:first).first(limit)
      end
    end
  end
end
