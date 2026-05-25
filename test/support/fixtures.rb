# frozen_string_literal: true

module Fixtures
  module_function

  def bookmarks_page
    load_json("x/bookmarks_page.json")
  end

  def bookmarks_page2
    load_json("x/bookmarks_page2.json")
  end

  def load_json(relative_path)
    JSON.parse(File.read(File.expand_path(File.join("../fixtures", relative_path), __dir__)))
  end
end
