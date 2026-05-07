# frozen_string_literal: true

module Fixtures
  module_function

  def bookmarks_page
    {
      "data" => [
        {
          "id" => "1001",
          "author_id" => "u1",
          "text" => "first tweet about ozempic",
          "created_at" => "2026-01-01T00:00:00.000Z",
          "conversation_id" => "1001",
          "attachments" => { "media_keys" => ["m1"] },
          "entities" => { "urls" => [{ "url" => "https://t.co/x", "expanded_url" => "https://example.com/a", "display_url" => "example.com/a" }] }
        },
        {
          "id" => "1002",
          "author_id" => "u2",
          "text" => "video tweet",
          "created_at" => "2026-01-02T00:00:00.000Z",
          "conversation_id" => "1002",
          "attachments" => { "media_keys" => ["v1"] }
        },
        {
          "id" => "1003",
          "author_id" => "u1",
          "text" => "quote tweet",
          "created_at" => "2026-01-03T00:00:00.000Z",
          "conversation_id" => "1003",
          "referenced_tweets" => [{ "type" => "quoted", "id" => "9999" }]
        }
      ],
      "includes" => {
        "users" => [
          { "id" => "u1", "username" => "alice", "name" => "Alice", "profile_image_url" => "https://x/p1.jpg" },
          { "id" => "u2", "username" => "bob", "name" => "Bob", "profile_image_url" => "https://x/p2.jpg" }
        ],
        "media" => [
          { "media_key" => "m1", "type" => "photo", "url" => "https://x/img.jpg", "width" => 800, "height" => 600 },
          { "media_key" => "v1", "type" => "video", "duration_ms" => 12000, "preview_image_url" => "https://x/preview.jpg",
            "variants" => [
              { "bit_rate" => 320000, "content_type" => "video/mp4", "url" => "https://x/low.mp4" },
              { "bit_rate" => 832000, "content_type" => "video/mp4", "url" => "https://x/hi.mp4" },
              { "content_type" => "application/x-mpegURL", "url" => "https://x/playlist.m3u8" }
            ] }
        ],
        "tweets" => [
          { "id" => "9999", "text" => "the quoted tweet", "author_id" => "u2", "created_at" => "2025-12-01T00:00:00.000Z" }
        ]
      },
      "meta" => { "next_token" => "page2", "result_count" => 3 }
    }
  end

  def bookmarks_page2
    {
      "data" => [
        { "id" => "1004", "author_id" => "u1", "text" => "later tweet", "created_at" => "2026-01-04T00:00:00.000Z" }
      ],
      "includes" => { "users" => [{ "id" => "u1", "username" => "alice", "name" => "Alice", "profile_image_url" => "https://x/p1.jpg" }] },
      "meta" => { "result_count" => 1 }
    }
  end
end
