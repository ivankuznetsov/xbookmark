# frozen_string_literal: true

require "test_helper"

require "tmpdir"
require "fileutils"
require "xbookmark/enrich/note_source"

describe Xbookmark::Enrich::NoteSource do
  # Mirrors the layout BookmarkRenderer#body_for produces, including a media
  # caption and a transcript, so the parser is tested against the real shape.
  def note(summary: "Samo Burja argues prehistoric humans are underrated.")
    <<~MD
      ---
      xbookmark_schema: 1
      tweet_id: '1394701316069470208'
      author: SamoBurja
      author_id: '956296561289453568'
      author_name: Samo Burja
      created_at: '2021-05-18T17:08:00.000Z'
      bookmarked_at: '2021-05-18T17:08:00.000Z'
      tags:
      - archaeology
      media:
      - path: media/1394701316069470208/E1r4c4ZWEAYeSw1.jpg
        kind: photo
        alt:
      thread: '1394701316069470208'
      links:
      - https://t.co/gIEuqAoLrZ
      summary: #{summary}
      enrichment_status: done
      concepts:
      - archaeology
      ---

      # Samo Burja on Prehistoric Humans

      #{summary}

      When we find the remains of beavers, we assume that they built dams.

      But when we find human skeletons, we imagine them naked. https://t.co/gIEuqAoLrZ

      ## Author

      [[authors/samoburja|@SamoBurja]]

      ## Concepts

      - [[concepts/archaeology|archaeology]]

      ## Media
      ![[media/1394701316069470208/E1r4c4ZWEAYeSw1.jpg]]

      Captions:
      - `E1r4c4ZWEAYeSw1.jpg`: A green-patinated excavated artifact at a dig site.

      ## Transcript

      ### clip.mp4

      #### Summary

      A short clip.

      #### Transcript

      Speaker 1: dig site footage narration.

      ## Source

      https://x.com/SamoBurja/status/1394701316069470208
    MD
  end

  it "reconstructs the bookmark, original text, captions, transcripts, and media from a note" do
    Dir.mktmpdir do |vault|
      path = File.join(vault, "bookmarks", "n.md")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, note)

      parsed = described_class.parse(path, vault_path: vault)

      bm = parsed.bookmark
      assert_equal "1394701316069470208", bm.tweet_id
      assert_equal "SamoBurja", bm.author_handle
      assert_equal "Samo Burja", bm.author_name
      # Original tweet text only — title heading and the summary paragraph are stripped.
      assert_includes bm.text, "When we find the remains of beavers"
      assert_includes bm.text, "human skeletons"
      refute_includes bm.text, "# Samo Burja on Prehistoric Humans"
      refute_includes bm.text, "argues prehistoric humans are underrated"

      assert_equal({ "E1r4c4ZWEAYeSw1.jpg" => "A green-patinated excavated artifact at a dig site." },
                   parsed.vision["captions"])
      assert_equal "Speaker 1: dig site footage narration.", parsed.transcripts["clip.mp4"]

      assert_equal [File.join(vault, "media/1394701316069470208/E1r4c4ZWEAYeSw1.jpg")],
                   parsed.media_records.map { |m| m[:path] }
      assert_equal "photo", parsed.media_records.first[:kind]
      assert_empty parsed.image_paths
      assert_equal 1, parsed.schema
    end
  end

  it "falls back to the summary when the body carries no original text beyond it" do
    Dir.mktmpdir do |vault|
      path = File.join(vault, "n.md")
      File.write(path, <<~MD)
        ---
        tweet_id: '5'
        author: bob
        summary: Just the summary here.
        ---

        # Title

        Just the summary here.

        ## Source

        https://x.com/bob/status/5
      MD

      parsed = described_class.parse(path, vault_path: vault)

      assert_equal "Just the summary here.", parsed.bookmark.text
    end
  end

  it "returns nil for a note without frontmatter" do
    Dir.mktmpdir do |vault|
      path = File.join(vault, "n.md")
      File.write(path, "no frontmatter here")

      assert_nil described_class.parse(path, vault_path: vault)
    end
  end

  it "returns nil for malformed frontmatter" do
    Dir.mktmpdir do |vault|
      path = File.join(vault, "n.md")
      File.write(path, "---\nkey: [unclosed\n---\nbody\n")

      assert_nil described_class.parse(path, vault_path: vault)
    end
  end
end
