# frozen_string_literal: true

require "test_helper"

require "xbookmark/sync/report"

describe Xbookmark::Sync::Report do
  it "summarizes skipped, transient, permanent, elapsed, and API page counts" do
    report = described_class.new
    report.synced = 2
    report.skipped = 1
    report.failed = 3
    report.permanent_errors = 4
    report.source_errors = 6
    report.elapsed = 1.24
    report.api_pages = 5

    assert_equal "synced 2, skipped 1, failed 3, retrying next run, permanent errors 4, source blocked 6, elapsed 1.2s, api pages 5",
                 report.to_s
  end

  it "defaults session_expired to false and omits it from the summary" do
    report = described_class.new
    refute report.session_expired
    assert_nil report.expired_source
    refute_includes report.to_s, "session expired"
  end

  it "summarizes a browser session expiry" do
    report = described_class.new
    report.session_expired = true
    report.expired_source = "browser"
    assert_includes report.to_s, "browser session expired (re-login)"
  end
end
