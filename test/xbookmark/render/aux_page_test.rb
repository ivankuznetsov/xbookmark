# frozen_string_literal: true

require "test_helper"

require "xbookmark/render/aux_page"
require "xbookmark/state/store"

describe Xbookmark::Render::TopicPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  let(:orch) do
    Class.new do
      def initialize
        @calls = 0
      end
      attr_reader :calls
      def summarize_topic(slug:, snippets:)
        @calls += 1
        "summary[#{@calls}]: #{snippets.size} bookmarks about #{slug}"
      end

      def summarize_author(handle:, snippets:)
        "author summary for #{handle}"
      end
    end.new
  end

  it "creates a topic page with an LLM summary on first reference" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["bookmark text 1"])
      assert_includes File.read(path), "summary[1]"
      assert_equal 1, orch.calls
    end
  end

  it "is a no-op when input set is unchanged" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["bookmark text 1"])
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["bookmark text 1"])
      assert_equal 1, orch.calls
    end
  end

  it "regenerates the summary when inputs change" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["b1"])
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["b1", "b2"])
      assert_equal 2, orch.calls
    end
  end

  it "falls back to a placeholder when topic summaries fail" do
    failing = stub("orch")
    failing.stubs(:summarize_topic).raises("codex down")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: failing)
      path = page.ensure!(slug: "broken", label: "Broken", inputs: ["snippet"])

      assert_includes File.read(path), "(no summary yet)"
    end
  end

  it "renders explicit post links when references are provided" do
    Dir.mktmpdir do |vault|
      references = {
        "ozempic" => [
          {
            target: "bookmarks/2026/01/01/alice-ozempic-1",
            label: "Ozempic trial result",
            author: "@alice",
            bookmarked_at: "2026-01-01T00:00:00Z"
          }
        ]
      }
      page = described_class.new(vault_path: vault, store: store, references: references)
      path = page.ensure!(slug: "ozempic", label: "Ozempic", inputs: [])

      content = File.read(path)
      assert_includes content, "## Posts"
      assert_includes content, "[[bookmarks/2026/01/01/alice-ozempic-1|Ozempic trial result]]"
      assert_includes content, "@alice, 2026-01-01"
    end
  end
end

describe Xbookmark::Render::AuthorPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "writes an author page with a label and summary" do
    orch = stub("orch", summarize_author: "alice posts a lot about health.")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "alice", label: "@alice", inputs: ["a1", "a2"])
      content = File.read(path)
      assert_includes content, "kind: author"
      assert_includes content, "alice posts a lot about health."
    end
  end

  it "falls back to a placeholder when author summaries fail" do
    orch = stub("orch")
    orch.stubs(:summarize_author).raises("codex down")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "alice", label: "@alice", inputs: ["a1"])

      assert_includes File.read(path), "(no summary yet)"
      assert_nil store.find_page("author", "alice")[:summary_input_digest]
    end
  end
end

describe Xbookmark::Render::EntityPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "uses topic-style summaries for entities and tolerates summary failures" do
    Dir.mktmpdir do |vault|
      orch = stub("orch", summarize_topic: "entity summary")
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "novo", label: "Novo", inputs: ["snippet"])
      assert_includes File.read(path), "entity summary"

      failing = stub("orch")
      failing.stubs(:summarize_topic).raises("codex down")
      failing_page = described_class.new(vault_path: vault, store: store, orchestrator: failing)
      failed_path = failing_page.ensure!(slug: "eli-lilly", label: "Eli Lilly", inputs: ["snippet"])
      assert_includes File.read(failed_path), "(no summary yet)"
    end
  end
end

describe Xbookmark::Render::ThreadPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "creates thread pages without an LLM summary hook" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: stub("orch"))
      path = page.ensure!(slug: "123", label: "thread 123", inputs: ["snippet"])

      assert path.end_with?("threads/123.md")
      assert_includes File.read(path), "kind: thread"
      assert_includes File.read(path), "(no summary yet)"
    end
  end
end

describe Xbookmark::Render::AuxPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "does not persist placeholder summaries as real summaries and survives unreadable existing pages" do
    Dir.mktmpdir do |vault|
      page = Xbookmark::Render::TopicPage.new(vault_path: vault, store: store)
      path = page.ensure!(slug: "placeholder", label: "Placeholder", inputs: [])
      assert_includes File.read(path), "(no summary yet)"
      assert_nil store.find_page("topic", "placeholder")[:summary_input_digest]

      store.upsert_page(kind: "topic", slug: "broken", path: "topics/broken.md", summary_input_digest: "old")
      FileUtils.mkdir_p(File.dirname(page.page_path("broken")))
      File.write(page.page_path("broken"), "existing")
      File.stubs(:read).with(page.page_path("broken")).raises(Errno::EACCES)
      page.ensure!(slug: "broken", label: "Broken", inputs: ["same"])
    end
  end
end
