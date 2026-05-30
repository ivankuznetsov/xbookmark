# frozen_string_literal: true

require "test_helper"

describe "README setup contract" do
  let(:readme) { File.read(File.expand_path("../README.md", __dir__)) }
  let(:env_example) { File.read(File.expand_path("../.env.example", __dir__)) }

  it "points new setups at the implemented scheduler command" do
    assert_includes readme, "bin/xbookmark install"
    refute_includes readme, "bin/xbookmark schedule"
    refute_includes readme, "Ask me whether to install"
  end

  it "does not document deferred commands or config flags as available" do
    deferred_surface = [
      "bin/xbookmark enrich",
      "auth refresh",
      "auth logout",
      "XBOOKMARK_CONFIG",
      "--config PATH",
      "--since YYYY-MM-DD",
      "[--type lex|vec|hyde]",
      "[--json]",
      "minitest"
    ]

    deferred_surface.each do |snippet|
      refute_includes readme, snippet
    end
  end

  it "describes the runtime bookmark wiki separately from the project wiki" do
    assert_includes readme, "XBOOKMARK_WIKI_PATH"
    assert_includes readme, "separate from this repository's `wiki/` project LLM wiki"
  end

  it "keeps redirect URI setup tied to env instead of a nonexistent port flag" do
    assert_includes env_example, "X_REDIRECT_URI=http://127.0.0.1:8765/callback"
    refute_includes env_example, "--port"
  end

  it "does not document a forced codex service tier" do
    refute_includes readme, 'service_tier = "flex"'
    refute_includes readme, 'service_tier = "fast"'
  end

  it "documents the four provider-secret subcommands" do
    %w[
      xbookmark\ auth\ login\ openrouter
      xbookmark\ auth\ bind\ openrouter
      xbookmark\ auth\ list
      xbookmark\ auth\ rm\ openrouter
    ].each do |snippet|
      assert_includes readme, snippet.gsub("\\ ", " ")
    end
  end

  it "documents the CI env-shortcut and canonical env-var form" do
    assert_includes readme, "XBOOKMARK_KEYS_FROM_ENV=1"
    assert_includes readme, "XBOOKMARK_OPENROUTER_KEY"
    assert_includes readme, "XBOOKMARK_X_KEY"
  end

  it "documents the auth.toml routing file path" do
    assert_includes readme, "~/.config/xbookmark/auth.toml"
  end
end
