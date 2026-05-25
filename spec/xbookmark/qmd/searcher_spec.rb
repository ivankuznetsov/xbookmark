# frozen_string_literal: true

require "xbookmark/qmd/searcher"
require "xbookmark/qmd/registrar"

RSpec.describe Xbookmark::Qmd::Searcher do
  let(:config) do
    Struct::XbookmarkConfig.new(
      vault_path: "/v", state_db_path: ":memory:", logs_dir: "/tmp",
      scratch_dir: "/v/.xbookmark/scratch",
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      env_file: nil, verbose: false
    )
  end

  let(:status) do
    Class.new do
      def success?; true; end
      def exitstatus; 0; end
    end.new
  end

  it "parses a JSON array result into hits" do
    json = [
      { "path" => "/v/bookmarks/2026/01/01/1.md", "score" => 0.91, "snippet" => "ozempic dose" },
      { "path" => "/v/bookmarks/2026/01/02/2.md", "score" => 0.55, "snippet" => "another" }
    ].to_json
    runner = ->(_argv) { [json, "", status] }
    hits = described_class.new(config: config, runner: runner).search("ozempic")
    expect(hits.size).to eq(2)
    expect(hits.first[:path]).to eq("/v/bookmarks/2026/01/01/1.md")
    expect(hits.first[:score]).to be_within(0.01).of(0.91)
  end

  it "parses a `{results: [...]}` envelope" do
    json = { "results" => [{ "path" => "/v/x.md", "score" => 1, "snippet" => "x" }] }.to_json
    runner = ->(_argv) { [json, "", status] }
    hits = described_class.new(config: config, runner: runner).search("x")
    expect(hits.first[:path]).to eq("/v/x.md")
  end

  it "enforces the requested limit even when qmd returns extra hits" do
    json = [
      { "path" => "/v/1.md", "score" => 3 },
      { "path" => "/v/2.md", "score" => 2 },
      { "path" => "/v/3.md", "score" => 1 }
    ].to_json
    runner = ->(_argv) { [json, "", status] }
    hits = described_class.new(config: config, runner: runner).search("x", limit: 2)
    expect(hits.map { |hit| hit[:path] }).to eq(["/v/1.md", "/v/2.md"])
  end

  it "returns [] when qmd binary is missing" do
    runner = ->(_argv) { raise Errno::ENOENT }
    expect { @hits = described_class.new(config: config, runner: runner).search("x") }
      .to output(/qmd binary not found/).to_stderr
    expect(@hits).to eq([])
  end

  it "returns [] and warns when qmd exits unsuccessfully" do
    failing_status = Class.new do
      def success?; false; end
      def exitstatus; 1; end
    end.new
    runner = ->(_argv) { ["", "boom", failing_status] }

    expect { @hits = described_class.new(config: config, runner: runner).search("x") }
      .to output(/qmd query failed: boom/).to_stderr
    expect(@hits).to eq([])
  end

  it "parses hits envelopes, rank/context aliases, empty output, and integer statuses" do
    hits_json = { "hits" => [{ "file" => "/v/hit.md", "rank" => "7", "context" => "ctx" }] }.to_json
    runner = ->(_argv) { [hits_json, "", 0] }

    hits = described_class.new(config: config, runner: runner).search("x")

    expect(hits).to eq([{ path: "/v/hit.md", score: 7.0, snippet: "ctx" }])

    empty = described_class.new(config: config, runner: ->(_argv) { ["", "", 0] }).search("x")
    expect(empty).to eq([])
  end

  it "raises and diagnoses non-JSON qmd output" do
    runner = ->(_argv) { ["not json", "", status] }
    searcher = described_class.new(config: config, runner: runner)

    expect { searcher.search("x") }
      .to output(/qmd output was not JSON:.*qmd raw output: not json/m).to_stderr
      .and raise_error(JSON::ParserError)
  end

  it "uses Open3 capture when no runner is injected" do
    searcher = described_class.new(config: config)

    out, err, status = searcher.send(:capture, [RbConfig.ruby, "-e", "STDOUT.write 'ok'; STDERR.write 'err'"])

    expect(out).to eq("ok")
    expect(err).to eq("err")
    expect(status).to be_success
  end
end
