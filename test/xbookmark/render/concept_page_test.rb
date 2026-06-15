# frozen_string_literal: true

require "test_helper"
require "yaml"

require "xbookmark/render/concept_page"
require "xbookmark/taxonomy/concept"

describe Xbookmark::Render::ConceptPage do
  it "renders broader concept links with labels" do
    concept = Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", broader: %w[venezuela oil])
    md = described_class.new(vault_path: "/vault").render(concept)

    assert_includes md, "[[concepts/venezuela|Venezuela]]"
    assert_includes md, "[[concepts/oil|Oil]]"
  end

  it "keeps hostile labels and aliases from corrupting headings while staying valid YAML" do
    concept = Xbookmark::Taxonomy::Concept.new(slug: "foo", label: "Foo]]bar",
                                               aliases: ["multi\nline", "---"], broader: ["a]]b"])
    md = described_class.new(vault_path: "/vault").render(concept)

    assert_includes md, "# Foo bar"            # heading is wikilink-safe
    assert_includes md, "[[concepts/a-b|A B]]" # broader slug is cleaned before linking
    front = YAML.safe_load(md.split("---\n", 3)[1])
    assert_equal "Foo]]bar", front["label"]
    assert_includes front["aliases"], "multi line" # newline collapsed
    refute_includes front["aliases"], "---"        # YAML doc-marker alias dropped
  end
end
