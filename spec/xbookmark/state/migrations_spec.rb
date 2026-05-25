# frozen_string_literal: true

require "xbookmark/state/migrations"
require "sqlite3"

RSpec.describe Xbookmark::State::Migrations do
  it "returns zero when schema version cannot be read yet" do
    db = instance_double(SQLite3::Database)
    allow(db).to receive(:get_first_value).and_raise(SQLite3::SQLException, "no table")

    expect(described_class.current_version(db)).to eq(0)
  end
end
