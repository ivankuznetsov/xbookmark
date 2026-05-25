# frozen_string_literal: true

require "xbookmark/render/aux_page"
require "xbookmark/state/store"

RSpec.describe Xbookmark::Render::TopicPage do
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
      expect(File.read(path)).to include("summary[1]")
      expect(orch.calls).to eq(1)
    end
  end

  it "is a no-op when input set is unchanged" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["bookmark text 1"])
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["bookmark text 1"])
      expect(orch.calls).to eq(1)
    end
  end

  it "regenerates the summary when inputs change" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["b1"])
      page.ensure!(slug: "ozempic", label: "Ozempic", inputs: ["b1", "b2"])
      expect(orch.calls).to eq(2)
    end
  end

  it "falls back to a placeholder when topic summaries fail" do
    failing = double(:orch)
    allow(failing).to receive(:summarize_topic).and_raise("codex down")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: failing)
      path = page.ensure!(slug: "broken", label: "Broken", inputs: ["snippet"])

      expect(File.read(path)).to include("(no summary yet)")
    end
  end
end

RSpec.describe Xbookmark::Render::AuthorPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "writes an author page with a label and summary" do
    orch = double(:orch, summarize_author: "alice posts a lot about health.")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "alice", label: "@alice", inputs: ["a1", "a2"])
      content = File.read(path)
      expect(content).to include("kind: author")
      expect(content).to include("alice posts a lot about health.")
    end
  end

  it "falls back to a placeholder when author summaries fail" do
    orch = double(:orch)
    allow(orch).to receive(:summarize_author).and_raise("codex down")
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "alice", label: "@alice", inputs: ["a1"])

      expect(File.read(path)).to include("(no summary yet)")
      expect(store.find_page("author", "alice")[:summary_input_digest]).to be_nil
    end
  end
end

RSpec.describe Xbookmark::Render::EntityPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "uses topic-style summaries for entities and tolerates summary failures" do
    Dir.mktmpdir do |vault|
      orch = double(:orch, summarize_topic: "entity summary")
      page = described_class.new(vault_path: vault, store: store, orchestrator: orch)
      path = page.ensure!(slug: "novo", label: "Novo", inputs: ["snippet"])
      expect(File.read(path)).to include("entity summary")

      failing = double(:orch)
      allow(failing).to receive(:summarize_topic).and_raise("codex down")
      failing_page = described_class.new(vault_path: vault, store: store, orchestrator: failing)
      failed_path = failing_page.ensure!(slug: "eli-lilly", label: "Eli Lilly", inputs: ["snippet"])
      expect(File.read(failed_path)).to include("(no summary yet)")
    end
  end
end

RSpec.describe Xbookmark::Render::ThreadPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "creates thread pages without an LLM summary hook" do
    Dir.mktmpdir do |vault|
      page = described_class.new(vault_path: vault, store: store, orchestrator: double(:orch))
      path = page.ensure!(slug: "123", label: "thread 123", inputs: ["snippet"])

      expect(path).to end_with("threads/123.md")
      expect(File.read(path)).to include("kind: thread")
      expect(File.read(path)).to include("(no summary yet)")
    end
  end
end

RSpec.describe Xbookmark::Render::AuxPage do
  let(:store) { Xbookmark::State::Store.new(":memory:") }

  it "does not persist placeholder summaries as real summaries and survives unreadable existing pages" do
    Dir.mktmpdir do |vault|
      page = Xbookmark::Render::TopicPage.new(vault_path: vault, store: store)
      path = page.ensure!(slug: "placeholder", label: "Placeholder", inputs: [])
      expect(File.read(path)).to include("(no summary yet)")
      expect(store.find_page("topic", "placeholder")[:summary_input_digest]).to be_nil

      store.upsert_page(kind: "topic", slug: "broken", path: "topics/broken.md", summary_input_digest: "old")
      FileUtils.mkdir_p(File.dirname(page.page_path("broken")))
      File.write(page.page_path("broken"), "existing")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(page.page_path("broken")).and_raise(Errno::EACCES)
      expect { page.ensure!(slug: "broken", label: "Broken", inputs: ["same"]) }.not_to raise_error
    end
  end
end
