# frozen_string_literal: true

require "xbookmark/render/wikilinks"

RSpec.describe Xbookmark::Render::Wikilinks do
  it "produces deterministic kebab-case slugs" do
    expect(described_class.slug("LLM agents")).to eq("llm-agents")
    expect(described_class.slug("Novo Nordisk")).to eq("novo-nordisk")
    expect(described_class.slug("  --AI/ML--  ")).to eq("ai-ml")
  end

  it "falls back to 'untitled' for empty input" do
    expect(described_class.slug("***")).to eq("untitled")
    expect(described_class.slug("")).to eq("untitled")
  end

  it "author_slug strips leading @ and non-handle chars" do
    expect(described_class.author_slug("@Alice")).to eq("alice")
    expect(described_class.author_slug("Bob_Smith")).to eq("bob_smith")
  end

  it "renders wikilinks with optional label" do
    expect(described_class.link("topics/llm-agents", "LLM agents"))
      .to eq("[[topics/llm-agents|LLM agents]]")
    expect(described_class.link("topics/foo", "topics/foo"))
      .to eq("[[topics/foo]]")
  end
end
