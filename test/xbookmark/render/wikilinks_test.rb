# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/wikilinks"

describe Xbookmark::Render::Wikilinks do
  it "produces deterministic kebab-case slugs" do
    assert_equal "llm-agents", described_class.slug("LLM agents")
    assert_equal "novo-nordisk", described_class.slug("Novo Nordisk")
    assert_equal "ai-ml", described_class.slug("  --AI/ML--  ")
  end

  it "falls back to 'untitled' for empty input" do
    assert_equal "untitled", described_class.slug("***")
    assert_equal "untitled", described_class.slug("")
  end

  it "author_slug strips leading @ and non-handle chars" do
    assert_equal "alice", described_class.author_slug("@Alice")
    assert_equal "bob_smith", described_class.author_slug("Bob_Smith")
  end

  it "renders wikilinks with optional label" do
    assert_equal "[[topics/llm-agents|LLM agents]]",
                 described_class.link("topics/llm-agents", "LLM agents")
    assert_equal "[[topics/foo]]", described_class.link("topics/foo", "topics/foo")
  end

  it "creates deterministic slugs for external URLs" do
    assert_equal "example-com-some-path-q-1", described_class.link_slug("https://example.com/Some Path?q=1")
    assert_equal "example-com", described_class.link_slug("http://example.com")
  end
end
