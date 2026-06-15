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
end
