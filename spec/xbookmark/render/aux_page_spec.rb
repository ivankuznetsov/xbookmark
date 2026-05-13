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
end
