# frozen_string_literal: true

require "test_helper"

require "xbookmark/state/migrations"
require "sqlite3"

describe Xbookmark::State::Migrations do
  it "returns zero when schema version cannot be read yet" do
    db = mock("sqlite database")
    db.stubs(:get_first_value).raises(SQLite3::SQLException, "no table")

    assert_equal 0, described_class.current_version(db)
  end
end
