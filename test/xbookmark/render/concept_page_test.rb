# frozen_string_literal: true

require "test_helper"
require "yaml"

require "xbookmark/render/concept_page"
require "xbookmark/taxonomy/concept"
require "xbookmark/taxonomy/registry"

describe Xbookmark::Render::ConceptPage do
  it "coerces legacy and unknown concept kinds into the closed vocabulary" do
    assert_equal "idea", Xbookmark::Taxonomy::Concept.new(slug: "x", kind: "topic").kind
    assert_equal "idea", Xbookmark::Taxonomy::Concept.new(slug: "y", kind: "bogus").kind
    assert_equal "organization", Xbookmark::Taxonomy::Concept.new(slug: "z", kind: "Org").kind
  end

  it "renders broader concept links with labels" do
    concept = Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", broader: %w[venezuela oil])
    md = described_class.new(vault_path: "/vault").render(concept)

    assert_includes md, "[[concepts/venezuela|Venezuela]]"
    assert_includes md, "[[concepts/oil|Oil]]"
  end

  it "drops generic legacy roots from frontmatter broader and graph links, and writes a single kind key" do
    concept = Xbookmark::Taxonomy::Concept.new(slug: "apple", label: "Apple", kind: "organization",
                                               broader: %w[entities technology])
    md = described_class.new(vault_path: "/vault").render(concept)

    front = YAML.safe_load(md.split("---\n", 3)[1])
    assert_equal ["technology"], front["broader"]   # generic root stripped
    refute_includes md, "[[concepts/entities"
    assert_includes md, "[[concepts/technology|Technology]]"
    # Single semantic kind, no dual page-type/concept_kind pair.
    assert_equal "organization", front["kind"]
    refute front.key?("concept_kind")
  end

  it "renders direct and inherited post references from bookmark notes" do
    Dir.mktmpdir do |vault|
      FileUtils.mkdir_p(File.join(vault, "bookmarks", "2026", "01", "01"))
      File.write(File.join(vault, "bookmarks", "2026", "01", "01", "post.md"), <<~MD)
        ---
        tweet_id: "1"
        author: alice
        bookmarked_at: "2026-01-01T00:00:00Z"
        summary: "Venezuela oil policy update"
        concepts:
        - venezuela-oil
        ---

        # fallback title
      MD
      parent = Xbookmark::Taxonomy::Concept.new(slug: "venezuela", label: "Venezuela")
      child = Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", broader: ["venezuela"])
      references = described_class.references_by_concept(vault_path: vault, concepts: [parent, child])

      md = described_class.new(vault_path: vault, references: references).render(parent)

      assert_includes md, "## Posts"
      assert_includes md, "[[bookmarks/2026/01/01/post|Venezuela oil policy update]]"
      assert_includes md, "@alice, 2026-01-01"
    end
  end

  it "skips bookmark notes with malformed YAML when collecting post references" do
    Dir.mktmpdir do |vault|
      FileUtils.mkdir_p(File.join(vault, "bookmarks"))
      File.write(File.join(vault, "bookmarks", "bad.md"), "---\n: bad: yaml\n---\n")

      assert_empty described_class.references_by_concept(vault_path: vault)
    end
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

  it "round-trips concept_kind and degrades malformed concept pages" do
    Dir.mktmpdir do |vault|
      concept = Xbookmark::Taxonomy::Concept.new(slug: "venezuela-oil", label: "Venezuela oil", kind: "subtopic")
      described_class.new(vault_path: vault).ensure!(concept)
      File.write(File.join(vault, "concepts", "bad.md"), "---\n: bad: yaml\n---\n")

      registry = Xbookmark::Taxonomy::Registry.from_vault(vault)

      assert_equal "subtopic", registry.find("venezuela-oil").kind
      assert_equal "bad", registry.find("bad").slug
    end
  end
end
