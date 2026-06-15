# frozen_string_literal: true

require "test_helper"

require "xbookmark/taxonomy/auditor"
require "xbookmark/taxonomy/graph_health_report"
require "xbookmark/taxonomy/manifest"
require "xbookmark/taxonomy/path_safety"
require "xbookmark/taxonomy/rebuilder"
require "xbookmark/state/store"

describe "taxonomy audit and rebuild" do
  def config_for(vault)
    Struct::XbookmarkConfig.new(
      vault_path: vault, state_db_path: ":memory:", logs_dir: "/tmp",
      scratch_dir: File.join(vault, ".xbookmark", "scratch"),
      x_client_id: "c", x_client_secret: nil, x_redirect_uri: "x",
      x_user_id: "42", x_access_token: "t", x_refresh_token: nil,
      x_token_expires_at: nil, codex_bin: "codex",
      whisper_bin: nil, whisper_model: "base.en", qmd_bin: "qmd",
      daily_sync_time: "06:00", min_run_interval_hours: 20.0,
      taxonomy_maintenance: false, env_file: nil, verbose: false
    )
  end

  def write_note(path, front = {}, body = "body")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\n#{front.to_yaml(line_width: -1).sub(/^---\n?/, "")}---\n\n#{body}\n")
  end

  it "audits numeric nodes, duplicate aliases, compounds, and malformed frontmatter safely" do
    Dir.mktmpdir do |vault|
      write_note(File.join(vault, "bookmarks", "2026", "01", "01", "123.md"), "tweet_id" => "123")
      write_note(File.join(vault, "threads", "123.md"), "kind" => "thread")
      write_note(File.join(vault, "topics", "sleep-and-adhd.md"), "kind" => "topic")
      write_note(File.join(vault, "concepts", "a.md"), "aliases" => ["dup"])
      write_note(File.join(vault, "concepts", "b.md"), "aliases" => ["dup"], "broader" => ["a"])
      File.write(File.join(vault, "concepts", "bad.md"), "---\n: bad: yaml\n---\n")
      File.write(File.join(vault, "concepts", "array.md"), "---\n- not\n- a\n- hash\n---\n")

      report = Xbookmark::Taxonomy::Auditor.new(vault_path: vault).call

      assert_equal "proposed_changes", report.state
      assert_equal 1, report.counts[:numeric_bookmark_nodes]
      assert_equal 1, report.counts[:singleton_thread_pages]
      assert_equal 1, report.counts[:one_off_compound_topics]
      assert_equal 1, report.counts[:duplicate_alias_clusters]
    end
  end

  it "validates path allowlists and graph-health thresholds" do
    Dir.mktmpdir do |vault|
      FileUtils.mkdir_p(File.join(vault, "bookmarks"))
      File.write(File.join(vault, "bookmarks", "note.md"), "ok")
      FileUtils.mkdir_p(File.join(vault, ".xbookmark"))
      File.write(File.join(vault, ".xbookmark", "hidden.md"), "hidden")
      FileUtils.ln_s(File.join(vault, "bookmarks", "note.md"), File.join(vault, "bookmarks", "linked.md"))
      safety = Xbookmark::Taxonomy::PathSafety.new(vault_path: vault)

      assert_equal [File.join(vault, "bookmarks", "note.md")], safety.allowed_markdown_files
      refute safety.safe_read_path?(File.join(vault, "..", "outside.md"))
      assert_raises(ArgumentError) { safety.validate_write_path!(File.join(vault, "..", "outside.md")) }
      assert_raises(ArgumentError) { safety.validate_write_path!(File.join(vault, "bookmarks", "linked.md")) }
      Pathname.any_instance.stubs(:relative_path_from).raises(ArgumentError, "different roots")
      refute safety.safe_read_path?(File.join(vault, "bookmarks", "note.md"))
      Pathname.any_instance.unstub(:relative_path_from)

      ready = Xbookmark::Taxonomy::GraphHealthReport.new(
        before: {},
        after: { numeric_bookmark_nodes: 0, singleton_thread_pages: 0, orphan_concepts: 0, concept_pages: 1, source_notes: 1 }
      )
      refute Xbookmark::Taxonomy::GraphHealthReport.new(before: { numeric_bookmark_nodes: 1, concept_pages: 0 }).ready?
      refute Xbookmark::Taxonomy::GraphHealthReport.new(
        before: {},
        after: { numeric_bookmark_nodes: 0, singleton_thread_pages: 0, concept_pages: 0, source_notes: 1 }
      ).ready?
      assert ready.ready?
      path = ready.write(File.join(vault, ".xbookmark", "graph.json"))
      assert_equal true, JSON.parse(File.read(path))["ready"]
    end
  end

  it "applies readable renames, prunes numeric threads, snapshots, manifests, and reindexes" do
    Dir.mktmpdir do |vault|
      store = Xbookmark::State::Store.new(":memory:")
      store.upsert_pending(tweet_id: "123", author_handle: "alice", bookmarked_at: "2026-01-01T00:00:00Z")
      store.upsert_page(kind: "thread", slug: "123", path: "threads/123.md")
      write_note(File.join(vault, "bookmarks", "2026", "01", "01", "123.md"),
                 { "tweet_id" => "123", "author" => "alice", "bookmarked_at" => "2026-01-01T00:00:00Z",
                   "summary" => "Great topic", "thread" => "threads/123" },
                 "bookmark body\n\n## Thread\n\n[[threads/123|thread 123]]")
      write_note(File.join(vault, "bookmarks", "2026", "01", "01", "already-readable.md"), { "tweet_id" => "999" })
      write_note(File.join(vault, "threads", "123.md"), "kind" => "thread")
      registrar = mock("registrar")
      registrar.expects(:ensure_registered!)
      registrar.expects(:index!).returns(:indexed)

      report = Xbookmark::Taxonomy::Rebuilder.new(
        config: config_for(vault),
        store: store,
        registrar: registrar,
        clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) }
      ).call(apply: true)

      renamed_path = File.join(vault, "bookmarks", "2026", "01", "01", "alice-great-topic-123.md")
      assert_equal "applied", report.state
      assert File.exist?(renamed_path)
      refute File.exist?(File.join(vault, "threads", "123.md"))
      # Legacy thread links are rewritten before the thread page is pruned.
      renamed = File.read(renamed_path)
      refute_includes renamed, "[[threads/123"
      refute_includes renamed, "thread: threads/123"
      manifest = JSON.parse(File.read(report.manifest_path))
      assert manifest["operations"].any? { |op| op["type"] == "rename" }
      assert manifest["operations"].any? { |op| op["type"] == "prune_thread" }
      assert manifest["operations"].any? { |op| op["type"] == "link_rewrite" }
      assert manifest["operations"].any? { |op| op["type"] == "qmd_reindex" && op["status"] == "indexed" }
      assert File.directory?(manifest["snapshot_path"])
      assert report.snapshot_path
      assert_equal "bookmarks/2026/01/01/alice-great-topic-123.md", store.find_bookmark("123")[:markdown_path]
      # The orphaned thread page row is removed from the state DB.
      assert_nil store.find_page("thread", "123")
    end
  end

  it "records a failed qmd reindex without aborting the apply" do
    Dir.mktmpdir do |vault|
      store = Xbookmark::State::Store.new(":memory:")
      write_note(File.join(vault, "bookmarks", "2026", "01", "01", "123.md"), { "tweet_id" => "123" }, "body")
      registrar = mock("registrar")
      registrar.stubs(:ensure_registered!)
      registrar.stubs(:index!).raises("qmd down")

      report = Xbookmark::Taxonomy::Rebuilder.new(
        config: config_for(vault), store: store, registrar: registrar, clock: -> { Time.utc(2026, 1, 2) }
      ).call(apply: true)

      assert_equal "applied", report.state
      manifest = JSON.parse(File.read(report.manifest_path))
      reindex = manifest["operations"].find { |op| op["type"] == "qmd_reindex" }
      assert_equal "failed", reindex["status"]
      assert_equal "qmd down", reindex["error"]
    end
  end

  it "rolls back to the snapshot and reports partial_failure when a state write fails mid-apply" do
    Dir.mktmpdir do |vault|
      store = Xbookmark::State::Store.new(":memory:")
      original = File.join(vault, "bookmarks", "2026", "01", "01", "123.md")
      write_note(original, { "tweet_id" => "123", "author" => "alice", "summary" => "Great topic" }, "body")
      store.stubs(:update_bookmark_path!).raises("db boom")

      report = Xbookmark::Taxonomy::Rebuilder.new(
        config: config_for(vault), store: store, clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) }
      ).call(apply: true)

      assert_equal "partial_failure", report.state
      assert report.snapshot_path
      assert_includes report.skipped.first, "db boom"
      assert File.exist?(report.manifest_path)
      # Snapshot restore: the original numeric note is back, the rename undone.
      assert File.exist?(original)
      refute File.exist?(File.join(vault, "bookmarks", "2026", "01", "01", "alice-great-topic-123.md"))
    end
  end

  it "supports dry-run, no-registrar apply, lock failure, parse fallback, and partial failure states" do
    Dir.mktmpdir do |vault|
      store = Xbookmark::State::Store.new(":memory:")
      clean = Xbookmark::Taxonomy::Rebuilder.new(config: config_for(vault), store: store).call(apply: true)
      assert_equal "clean", clean.state
      refute Dir.exist?(File.join(vault, ".xbookmark", "snapshots"))

      write_note(File.join(vault, "bookmarks", "2026", "01", "01", "123.md"), "tweet_id" => "123")
      rebuilder = Xbookmark::Taxonomy::Rebuilder.new(config: config_for(vault), store: store,
                                                     clock: -> { Time.utc(2026, 1, 2) })

      assert_equal "proposed_changes", rebuilder.call.state
      File.write(File.join(vault, "bookmarks", "2026", "01", "01", "456.md"), "---\n: bad: yaml\n---\nbody")
      assert_equal "applied", rebuilder.call(apply: true).state

      locked = File.join(vault, ".xbookmark", "taxonomy.lock")
      File.open(locked, "w") do |file|
        file.flock(File::LOCK_EX)
        assert_raises(RuntimeError) { rebuilder.send(:with_lock) { true } }
      end

      Xbookmark::Taxonomy::Auditor.any_instance.stubs(:metrics).raises("audit failed")
      partial = rebuilder.call(apply: true)
      assert_equal "partial_failure", partial.state
      assert_includes partial.skipped.first, "audit failed"
    end
  end

  it "records manifest details and report formatting" do
    Dir.mktmpdir do |vault|
      manifest = Xbookmark::Taxonomy::Manifest.new(path: File.join(vault, ".xbookmark", "m.json"))
      manifest.add(:rename, "old_path" => "old.md")
      path = manifest.write(snapshot_path: "snap", graph_health_path: "graph")
      parsed = JSON.parse(File.read(path))

      assert_equal "snap", parsed["snapshot_path"]
      assert parsed["manifest_hash"]
      report = Xbookmark::Taxonomy::Report.new(state: "blocked_conflicts", counts: { a: 1 },
                                               manifest_path: "m", graph_health_path: "g", skipped: ["x"])
      assert_equal 2, report.exit_code
      refute report.clean?
      assert_includes report.to_s, "skipped=x"
    end
  end
end
