# frozen_string_literal: true

require "test_helper"

require "xbookmark/enrich/codex"

describe Xbookmark::Enrich::Codex do
  it "happy path: parses JSON and enforces schema" do
    fake = FakeCodex.new.push({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    result = codex.run(prompt: "hi", json_schema: schema)
    assert_hash_includes({ "tags" => ["a"] }, result)
    assert_equal "codex", fake.calls.first.first
    assert_includes fake.calls.first, "--json"
  end

  it "injects the --model flag only when a model override is set" do
    with_model = FakeCodex.new.push({ "tags" => ["a"] })
    described_class.new(bin: "codex", runner: with_model, model: "gpt-5.4-mini")
      .run(prompt: "x", json_schema: { "type" => "object", "required" => %w[tags] })
    assert_equal %w[--model gpt-5.4-mini], with_model.calls.first.each_cons(2).find { |a, _| a == "--model" }

    without_model = FakeCodex.new.push({ "tags" => ["a"] })
    described_class.new(bin: "codex", runner: without_model)
      .run(prompt: "x", json_schema: { "type" => "object", "required" => %w[tags] })
    refute_includes without_model.calls.first, "--model"
  end

  it "injects model_reasoning_effort config only when an override is set" do
    with_effort = FakeCodex.new.push({ "tags" => ["a"] })
    described_class.new(bin: "codex", runner: with_effort, reasoning_effort: "low")
      .run(prompt: "x", json_schema: { "type" => "object", "required" => %w[tags] })
    argv = with_effort.calls.first
    idx = argv.index("-c")
    assert idx, "expected a -c config flag"
    assert_equal 'model_reasoning_effort="low"', argv[idx + 1]

    without_effort = FakeCodex.new.push({ "tags" => ["a"] })
    described_class.new(bin: "codex", runner: without_effort)
      .run(prompt: "x", json_schema: { "type" => "object", "required" => %w[tags] })
    refute_includes without_effort.calls.first, "-c"
  end

  it "passes prompts over stdin instead of argv" do
    prompt = "x" * 200_000
    fake = FakeCodex.new.push({ "tags" => ["a"] })
    codex = described_class.new(bin: "codex", runner: fake)

    codex.run(prompt: prompt, json_schema: { "type" => "object", "required" => %w[tags] })

    assert_equal ["--", "-"], fake.calls.first.last(2)
    refute_includes fake.calls.first, prompt
    assert_equal prompt, fake.stdin_inputs.first
  end

  it "raises CodexError when codex exits non-zero" do
    fake = FakeCodex.new.push(2) # exit code
    codex = described_class.new(bin: "codex", runner: fake)
    error = assert_raises(Xbookmark::CodexError) { codex.run(prompt: "x") }
    assert_match(/exited 2/, error.message)
  end

  it "raises PermanentError when output fails schema (consistently wrong shape is not transient)" do
    fake = FakeCodex.new.push({ "tags" => ["a"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics] }
    error = assert_raises(Xbookmark::PermanentError) { codex.run(prompt: "x", json_schema: schema) }
    assert_match(/schema validation/, error.message)
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
    assert_hash_includes({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] }, result)
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
    assert_hash_includes({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] }, result)
  end

  it "passes images as discrete --image argv entries" do
    fake = FakeCodex.new.push({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] })
    codex = described_class.new(bin: "codex", runner: fake)
    schema = { "type" => "object", "required" => %w[tags topics entities] }
    codex.run(prompt: "describe", images: ["/tmp/a.jpg", "/tmp/b.jpg"], json_schema: schema)
    argv = fake.calls.first
    image_args = argv.each_cons(2).select { |a, _| a == "--image" }.map(&:last)
    assert_equal ["/tmp/a.jpg", "/tmp/b.jpg"], image_args
  end

  it "returns raw stdout without schema and passes extra argv through" do
    fake = FakeCodex.new.push("plain answer")
    codex = described_class.new(bin: "codex", runner: fake)

    assert_equal "plain answer", codex.run(prompt: "describe", extra_argv: ["--model", "gpt-test"])
    assert_includes fake.calls.first, "--model"
    assert_includes fake.calls.first, "gpt-test"
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
      assert_hash_includes({ "tags" => ["a"], "topics" => ["b"], "entities" => ["c"] }, result)
    end
  end

  it "diagnoses non-JSON stdout and invalid fallback JSON" do
    schema = { "type" => "object", "required" => %w[tags] }
    error = assert_raises(Xbookmark::CodexError) do
      described_class.new(bin: "codex", runner: FakeCodex.new.push("no json here")).run(prompt: "x", json_schema: schema)
    end
    assert_match(/stdout was not JSON/, error.message)

    error = assert_raises(Xbookmark::CodexError) do
      described_class.new(bin: "codex", runner: FakeCodex.new.push("{bad json")).run(prompt: "x", json_schema: schema)
    end
    assert_match(/JSON parse failed/, error.message)
  end

  it "invokes subprocesses with timeout handling" do
    codex = described_class.new(bin: "codex")
    out, err, status = codex.send(:invoke_with_timeout, [RbConfig.ruby, "-e", "STDOUT.write STDIN.read; STDERR.write 'warn'"], 2, stdin_data: "ok")

    assert_equal "ok", out
    assert_equal "warn", err
    assert status.success?

    error = assert_raises(Xbookmark::CodexError) do
      codex.send(:invoke_with_timeout, [RbConfig.ruby, "-e", "sleep 5"], 0.01)
    end
    assert_match(/exceeded timeout/, error.message)
  end

  it "ignores broken stdin pipes after the child exits early" do
    broken_stdin = mock("stdin")
    broken_stdin.expects(:write).with("prompt").raises(Errno::EPIPE)
    broken_stdin.expects(:close)

    assert_nil described_class.new(bin: "codex").send(:write_stdin, broken_stdin, "prompt")
  end

  it "routes through invoke_with_timeout when no runner is injected" do
    codex = described_class.new(bin: "codex")
    status = process_status(success: true, exitstatus: 0)
    codex.stubs(:invoke_with_timeout).with(["codex"], 1, stdin_data: "prompt").returns(["{}", "", status])

    assert_equal ["{}", "", status], codex.send(:invoke, ["codex"], stdin_data: "prompt", timeout: 1)
  end

  it "skips non-JSON model-message payloads before falling back to raw JSON parsing" do
    raw = { "type" => "agent_message", "content" => "not json" }.to_json

    assert_equal(
      { "type" => "agent_message", "content" => "not json" },
      described_class.new(bin: "codex").send(:parse_json!, raw)
    )
  end
end
