# frozen_string_literal: true

require "test_helper"

require "ostruct"
require "xbookmark/render/path_builder"

describe Xbookmark::Render::PathBuilder do
  def bookmark(id: "1", text: "A useful title", author: "alice")
    OpenStruct.new(
      tweet_id: id,
      author_handle: author,
      text: text,
      bookmarked_at: "2026-01-01T00:00:00Z",
      created_at: "2026-01-01T00:00:00Z"
    )
  end

  it "derives the filename from the enrichment title when present" do
    Dir.mktmpdir do |vault|
      builder = described_class.new(vault_path: vault)
      bm = bookmark(id: "42", text: "raw verbose tweet text", author: "alice")
      enrichment = OpenStruct.new(title: "Retatrutide Phase 3 Results",
                                  summary: "a long verbose summary that should not drive the filename")

      assert_equal "alice-retatrutide-phase-3-results-42.md", builder.filename_for(bm, enrichment: enrichment)
    end
  end

  it "honors persisted absolute and relative paths" do
    builder = described_class.new(vault_path: "/vault")

    assert_equal "/already.md", builder.path_for(bookmark, existing_path: "/already.md")
    assert_equal "/vault/bookmarks/old.md", builder.path_for(bookmark, existing_path: "bookmarks/old.md")
  end

  it "adds deterministic collision suffixes and reserved-name fallbacks" do
    Dir.mktmpdir do |vault|
      builder = described_class.new(vault_path: vault)
      bm = bookmark(id: "123", text: "CON", author: nil)
      first = builder.filename_for(bm)
      collided = builder.filename_for(bm, taken_paths: [first])

      assert_equal "bookmark-123.md", first
      assert_match(/\Abookmark-[a-f0-9]{8}-123\.md\z/, collided)
    end
  end

  it "truncates long titles within the byte cap while keeping the tweet id suffix" do
    Dir.mktmpdir do |vault|
      builder = described_class.new(vault_path: vault)
      name = builder.filename_for(bookmark(id: "999", text: "word " * 80, author: "alice"))

      assert name.end_with?("-999.md"), name
      human = name.delete_suffix("-999.md")
      assert_operator human.bytesize, :<=, described_class::HUMAN_PREFIX_BYTES
    end
  end

  it "produces filesystem-safe ascii names for unicode titles, preserving the suffix" do
    Dir.mktmpdir do |vault|
      builder = described_class.new(vault_path: vault)
      name = builder.filename_for(bookmark(id: "42", text: "Привет мир 🌍 café", author: "alice"))

      assert name.end_with?("-42.md"), name
      assert_match(%r{\A[a-z0-9-]+-42\.md\z}, name)
    end
  end
end
