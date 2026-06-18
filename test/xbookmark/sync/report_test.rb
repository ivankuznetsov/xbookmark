# frozen_string_literal: true

require "test_helper"

require "xbookmark/sync/report"

describe Xbookmark::Sync::Report do
  it "summarizes skipped, transient, permanent, elapsed, and source page counts" do
    report = described_class.new
    report.synced = 2
    report.skipped = 1
    report.failed = 3
    report.permanent_errors = 4
    report.source_errors = 6
    report.elapsed = 1.24
    report.source_pages = 5

    assert_equal "synced 2, skipped 1, failed 3, retrying next run, permanent errors 4, source blocked 6, elapsed 1.2s, source pages 5",
                 report.to_s
  end

  it "defaults to not-expired (nil source) and omits it from the summary" do
    report = described_class.new
    refute report.session_expired?
    assert_nil report.expired_source
    refute_includes report.to_s, "session expired"
  end

  it "derives session_expired? from a marked browser expiry and summarizes it" do
    report = described_class.new
    report.mark_session_expired
    assert report.session_expired?, "session_expired? derives from a marked expiry"
    assert_equal "browser", report.expired_source
    assert_includes report.to_s, "browser session expired (re-login)"
  end

  it "is idempotent so a later block can't change the culprit (first-wins)" do
    report = described_class.new
    report.mark_session_expired
    report.mark_session_expired
    assert_equal "browser", report.expired_source
  end
end
