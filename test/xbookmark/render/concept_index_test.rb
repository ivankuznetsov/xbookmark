# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/concept_index"
require "xbookmark/taxonomy/concept"

describe Xbookmark::Render::ConceptIndex do
  it "lists root concepts and reports orphan and conflict counts" do
    Dir.mktmpdir do |vault|
      concepts = [
        Xbookmark::Taxonomy::Concept.new(slug: "venezuela", label: "Venezuela"),
        Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", broader: ["venezuela"])
      ]

      path = described_class.new(vault_path: vault).write(concepts, conflicts: 2)
      body = File.read(path)

      assert_includes body, "[[concepts/venezuela|Venezuela]]"
      # venezuela-oil has a broader link, so it is neither a root nor an orphan.
      refute_includes body, "[[concepts/venezuela-oil"
      assert_includes body, "- orphan_concepts: 1"
      assert_includes body, "- blocked_conflicts: 2"
    end
  end

  it "caps the root-concept list and notes how many were omitted" do
    Dir.mktmpdir do |vault|
      limit = Xbookmark::Render::ConceptIndex::ROOT_DISPLAY_LIMIT
      concepts = Array.new(limit + 5) { |i| Xbookmark::Taxonomy::Concept.new(slug: format("c%04d", i)) }

      body = File.read(described_class.new(vault_path: vault).write(concepts))

      assert_includes body, "_…and 5 more root concepts_"
      assert_equal limit, body.scan(/^- \[\[concepts\//).size
    end
  end
end
