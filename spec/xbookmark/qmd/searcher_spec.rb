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

  it "returns [] when qmd binary is missing" do
    runner = ->(_argv) { raise Errno::ENOENT }
    expect { @hits = described_class.new(config: config, runner: runner).search("x") }
      .to output(/qmd binary not found/).to_stderr
    expect(@hits).to eq([])
  end
end
