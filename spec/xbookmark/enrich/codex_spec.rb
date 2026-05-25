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

  it "passes prompts over stdin instead of argv" do
    prompt = "x" * 200_000
    fake = FakeCodex.new.push({ "tags" => ["a"] })
    codex = described_class.new(bin: "codex", runner: fake)

    codex.run(prompt: prompt, json_schema: { "type" => "object", "required" => %w[tags] })

    expect(fake.calls.first.last(2)).to eq(["--", "-"])
    expect(fake.calls.first).not_to include(prompt)
    expect(fake.stdin_inputs.first).to eq(prompt)
  end

  it "raises CodexError when codex exits non-zero" do
    fake = FakeCodex.new.push(2) # exit code
    codex = described_class.new(bin: "codex", runner: fake)
    expect { codex.run(prompt: "x") }.to raise_error(Xbookmark::CodexError, /exited 2/)
  end

  it "raises PermanentError when output fails schema (consistently wrong shape is not transient)" do
    fake = FakeCodex.new.push({ "tags" => ["a"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics] }
    expect { codex.run(prompt: "x", json_schema: schema) }
      .to raise_error(Xbookmark::PermanentError, /schema validation/)
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

  it "parses current codex item.completed agent_message streams" do
    fake = FakeCodex.new
    body = '{"tags":["a"],"topics":["b"],"entities":["c"]}'
    stream = [
      { "type" => "thread.started", "thread_id" => "t" },
      { "type" => "turn.started" },
      { "type" => "item.completed", "item" => { "id" => "i", "type" => "agent_message", "text" => body } },
      { "type" => "turn.completed", "usage" => { "input_tokens" => 1 } }
    ].map(&:to_json).join("\n")
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

  it "returns raw stdout without schema and passes extra argv through" do
    fake = FakeCodex.new.push("plain answer")
    codex = described_class.new(bin: "codex", runner: fake)

    expect(codex.run(prompt: "describe", extra_argv: ["--model", "gpt-test"])).to eq("plain answer")
    expect(fake.calls.first).to include("--model", "gpt-test")
  end

  it "parses alternate model-message payload shapes and ignores malformed JSONL noise" do
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    [
      { "type" => "model_message", "content" => { "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] } },
      { "type" => "agent_message", "message" => '{"tags":["a"],"topics":["b"],"entities":["c"]}' },
      { "type" => "item.completed", "item" => { "type" => "other", "content" => { "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] } } }
    ].each do |event|
      fake = FakeCodex.new.push("not-json\n#{event.to_json}\n")
      result = described_class.new(bin: "codex", runner: fake).run(prompt: "x", json_schema: schema)
      expect(result).to include("tags" => ["a"], "topics" => ["b"], "entities" => ["c"])
    end
  end

  it "diagnoses non-JSON stdout and invalid fallback JSON" do
    schema = { "type" => "object", "required" => %w[tags] }
    expect { described_class.new(bin: "codex", runner: FakeCodex.new.push("no json here")).run(prompt: "x", json_schema: schema) }
      .to raise_error(Xbookmark::CodexError, /stdout was not JSON/)

    expect { described_class.new(bin: "codex", runner: FakeCodex.new.push("{bad json")).run(prompt: "x", json_schema: schema) }
      .to raise_error(Xbookmark::CodexError, /JSON parse failed/)
  end

  it "invokes subprocesses with timeout handling" do
    codex = described_class.new(bin: "codex")
    out, err, status = codex.send(:invoke_with_timeout, [RbConfig.ruby, "-e", "STDOUT.write STDIN.read; STDERR.write 'warn'"], 2, stdin_data: "ok")

    expect(out).to eq("ok")
    expect(err).to eq("warn")
    expect(status).to be_success

    expect do
      codex.send(:invoke_with_timeout, [RbConfig.ruby, "-e", "sleep 5"], 0.01)
    end.to raise_error(Xbookmark::CodexError, /exceeded timeout/)
  end

  it "ignores broken stdin pipes after the child exits early" do
    broken_stdin = instance_double(IO)
    allow(broken_stdin).to receive(:write).and_raise(Errno::EPIPE)
    allow(broken_stdin).to receive(:close)

    expect(described_class.new(bin: "codex").send(:write_stdin, broken_stdin, "prompt")).to be_nil
    expect(broken_stdin).to have_received(:close)
  end

  it "routes through invoke_with_timeout when no runner is injected" do
    codex = described_class.new(bin: "codex")
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(codex).to receive(:invoke_with_timeout).and_return(["{}", "", status])

    expect(codex.send(:invoke, ["codex"], stdin_data: "prompt", timeout: 1)).to eq(["{}", "", status])
    expect(codex).to have_received(:invoke_with_timeout).with(["codex"], 1, stdin_data: "prompt")
  end

  it "skips non-JSON model-message payloads before falling back to raw JSON parsing" do
    raw = { "type" => "agent_message", "content" => "not json" }.to_json

    expect(described_class.new(bin: "codex").send(:parse_json!, raw))
      .to eq("type" => "agent_message", "content" => "not json")
  end
end
