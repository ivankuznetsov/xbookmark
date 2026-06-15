# frozen_string_literal: true

require "test_helper"

require "xbookmark/taxonomy/curator"
require "xbookmark/taxonomy/normalizer"
require "xbookmark/taxonomy/prompt_context"
require "xbookmark/taxonomy/registry"
require "xbookmark/state/store"

describe Xbookmark::Taxonomy::Normalizer do
  it "canonicalizes aliases and malformed slugs" do
    registry = Xbookmark::Taxonomy::Registry.new([
      Xbookmark::Taxonomy::Concept.new(slug: "adhd", aliases: ["attention deficit hyperactivity disorder"])
    ])
    normalizer = described_class.new(registry: registry)

    assert_equal ["adhd"], normalizer.normalize("ADHD").map(&:slug)
    assert_equal ["adhd"], normalizer.normalize("adhd-").map(&:slug)
    assert_equal ["adhd"], normalizer.normalize("attention deficit hyperactivity disorder").map(&:slug)
  end

  it "splits one-off conjunctions and low-recurrence demonym compounds" do
    normalizer = described_class.new

    assert_equal %w[sleep adhd], normalizer.normalize("sleep-and-adhd").map(&:slug)
    assert_equal %w[venezuela oil], normalizer.normalize("venezuelan-oil").map(&:slug)
  end

  it "keeps recurring child concepts with broader links and facets" do
    normalizer = described_class.new(recurrence_counts: { "venezuelan-economy" => 3 })
    concept = normalizer.normalize({ "label" => "venezuelan-economy", "kind" => "subtopic" }).first

    assert_equal "venezuela-economy", concept.slug
    assert_equal %w[venezuela economics], concept.broader
    assert_includes concept.facets, "area/venezuela"
    assert_includes concept.facets, "facet/economics"
  end
end

describe Xbookmark::Taxonomy::Registry do
  it "loads concepts from pages and store rows, preserving aliases" do
    Dir.mktmpdir do |vault|
      FileUtils.mkdir_p(File.join(vault, "concepts"))
      File.write(File.join(vault, "concepts", "venezuela.md"), <<~MD)
        ---
        slug: venezuela
        label: Venezuela
        kind: place
        aliases:
        - Venezuelan
        broader: []
        tags:
        - area/venezuela
        ---
      MD
      store = Xbookmark::State::Store.new(":memory:")
      store.upsert_concept(slug: "oil", label: "Oil", kind: "area", aliases: ["petroleum"], broader: [],
                           facets: ["facet/oil"], evidence_count: 2, confidence: 0.2)

      registry = described_class.from_vault(vault, store: store)

      assert registry.include?("Venezuelan")
      assert_equal "oil", registry.find("petroleum").slug
      assert_equal [], described_class.json_array("{bad")
    end
  end

  it "adds hash concepts and returns relevant sanitized prompt context" do
    registry = described_class.new
    registry.add(slug: "venezuela-politics", label: "Venezuela | politics]]", aliases: ["Bolivarian\npolitics"],
                 broader: ["venezuela", "politics"], evidence_count: 5)
    context = Xbookmark::Taxonomy::PromptContext.new(registry: registry, byte_limit: 1_000).for_labels(["venezuela"])

    assert_equal "venezuela-politics", context.first["slug"]
    refute_match(/\]\]|\||\n/, context.first["label"])
    assert_equal %w[venezuela politics], context.first["parents"]
  end
end

describe Xbookmark::Taxonomy::Curator do
  it "persists deterministic decisions and marks weak evidence as blocked" do
    store = Xbookmark::State::Store.new(":memory:")
    curator = described_class.new(store: store)

    decisions = curator.curate(["brand-new-concept"])

    assert_equal "blocked_conflicts", decisions.first["curation_state"]
    assert_equal "blocked_conflicts", store.concepts.first[:curator_outcome]
    assert_includes curator.prompt_for([{ "label" => "brand-new-concept" }]), "sanitized registry context"
    refute Xbookmark::Taxonomy::Concept.new(slug: "old", outcome: "alias").canonical?
  end
end
