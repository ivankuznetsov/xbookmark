# frozen_string_literal: true

require "xbookmark/enrich/codex"

RSpec.describe Xbookmark::Enrich::Codex do
  it "happy path: parses JSON and enforces schema" do
    fake = FakeCodex.new.push({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    result = codex.run(prompt: "hi", json_schema: schema)
    expect(result).to include("tags" => ["a"])
    expect(fake.calls.first.first).to eq("codex")
    expect(fake.calls.first).to include("--json")
  end

  it "raises CodexError when codex exits non-zero" do
    fake = FakeCodex.new.push(2) # exit code
    codex = described_class.new(bin: "codex", runner: fake)
    expect { codex.run(prompt: "x") }.to raise_error(Xbookmark::CodexError, /exited 2/)
  end

  it "raises CodexError when output fails schema" do
    fake = FakeCodex.new.push({ "tags" => ["a"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics] }
    expect { codex.run(prompt: "x", json_schema: schema) }
      .to raise_error(Xbookmark::CodexError, /schema validation/)
  end

  it "parses JSONL event streams emitted by codex --json" do
    fake = FakeCodex.new
    # Push a raw multi-line stream where the final line carries the body.
    body = '{"tags":["a"],"topics":["b"],"entities":["c"]}'
    stream = "{\"event\":\"start\"}\n{\"event\":\"progress\"}\n#{body}\n"
    fake.push(stream)
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    result = codex.run(prompt: "x", json_schema: schema)
    expect(result).to include("tags" => ["a"], "topics" => ["b"], "entities" => ["c"])
  end

  it "passes images as discrete --image argv entries" do
    fake = FakeCodex.new.push({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    codex.run(prompt: "describe", images: ["/tmp/a.jpg", "/tmp/b.jpg"], json_schema: schema)
    argv = fake.calls.first
    image_args = argv.each_cons(2).select { |a, _| a == "--image" }.map(&:last)
    expect(image_args).to eq(["/tmp/a.jpg", "/tmp/b.jpg"])
  end
end
