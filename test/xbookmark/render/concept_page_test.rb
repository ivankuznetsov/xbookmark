# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/concept_page"
require "xbookmark/taxonomy/concept"

describe Xbookmark::Render::ConceptPage do
  it "renders broader concept links with labels" do
    concept = Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", broader: %w[venezuela oil])
    md = described_class.new(vault_path: "/vault").render(concept)

    assert_includes md, "[[concepts/venezuela|Venezuela]]"
    assert_includes md, "[[concepts/oil|Oil]]"
  end
end
