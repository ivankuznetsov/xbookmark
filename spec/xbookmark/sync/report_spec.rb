# frozen_string_literal: true

require "xbookmark/sync/report"

RSpec.describe Xbookmark::Sync::Report do
  it "summarizes skipped, transient, permanent, elapsed, and API page counts" do
    report = described_class.new
    report.synced = 2
    report.skipped = 1
    report.failed = 3
    report.permanent_errors = 4
    report.elapsed = 1.24
    report.api_pages = 5

    expect(report.to_s)
      .to eq("synced 2, skipped 1, failed 3, retrying next run, permanent errors 4, elapsed 1.2s, api pages 5")
  end
end
