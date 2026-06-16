# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/session"

# Minimal Ferrum stand-ins so Session can be exercised without launching
# Chromium. They record what Session asks of them.
class FakePage
  attr_reader :visited, :closed

  def initialize(current_url: "https://x.com/i/bookmarks")
    @current_url = current_url
    @visited = []
    @closed = false
  end

  def go_to(url)
    @visited << url
  end

  def current_url
    @current_url
  end

  def close
    @closed = true
  end
end

class FakeFerrumBrowser
  attr_reader :options, :pages, :quit_count

  def initialize(options)
    @options = options
    @pages = []
    @quit_count = 0
  end

  def create_page
    page = FakePage.new
    @pages << page
    page
  end

  def quit
    @quit_count += 1
  end
end

describe Xbookmark::Browser::Session do
  let(:config) { Struct.new(:vault_path).new("/tmp/wiki") }

  def build_session(headless: true, browser_class: FakeFerrumBrowser, chromium_path: "/usr/bin/chromium")
    described_class.new(config: config, headless: headless, browser_class: browser_class, chromium_path: chromium_path)
  end

  it "builds the browser headless with the isolated profile dir and detected Chromium" do
    with_tmp_home do |home|
      session = build_session(chromium_path: "/usr/bin/chromium")
      browser = session.start

      assert_instance_of FakeFerrumBrowser, browser
      assert_equal true, browser.options[:headless]
      assert_equal "/usr/bin/chromium", browser.options[:browser_path]
      profile = File.join(home, ".config", "xbookmark", "browser-profile")
      assert_equal profile, browser.options[:save_path]
      assert_equal profile, browser.options[:browser_options]["user-data-dir"]
      assert Dir.exist?(profile), "profile dir should be created under the config dir"
      refute_includes profile, "Default", "must not be the user's everyday Chrome profile"
    end
  end

  it "builds a headed browser for one-time login" do
    with_tmp_home do
      browser = build_session(headless: false).start
      assert_equal false, browser.options[:headless]
    end
  end

  it "memoizes the browser across start calls" do
    with_tmp_home do
      session = build_session
      assert_same session.start, session.start
    end
  end

  it "detects Chromium when no explicit path is given" do
    with_tmp_home do
      Xbookmark::Browser::Chromium.stubs(:detect).returns("/opt/chromium")
      session = build_session(chromium_path: nil)
      assert_equal "/opt/chromium", session.start.options[:browser_path]
    end
  end

  it "raises an actionable ConfigError when no Chromium is installed" do
    with_tmp_home do
      Xbookmark::Browser::Chromium.stubs(:detect).returns(nil)
      session = build_session(chromium_path: nil)
      error = assert_raises(Xbookmark::ConfigError) { session.start }
      assert_match(/No Chromium/, error.message)
      assert_match(/never bundled/, error.message)
    end
  end

  it "reports logged_in? true when the bookmarks page stays on the bookmarks page" do
    with_tmp_home do
      session = build_session
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(FakePage.new(current_url: "https://x.com/i/bookmarks"))
      assert session.logged_in?
    end
  end

  it "reports logged_in? false when X redirects to the login flow" do
    with_tmp_home do
      session = build_session
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(FakePage.new(current_url: "https://x.com/i/flow/login"))
      refute session.logged_in?
    end
  end

  it "reports logged_in? false on a checkpoint interstitial" do
    with_tmp_home do
      session = build_session
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(FakePage.new(current_url: "https://x.com/account/access"))
      refute session.logged_in?
    end
  end

  it "reports logged_in? false when the page has no URL" do
    with_tmp_home do
      session = build_session
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(FakePage.new(current_url: ""))
      refute session.logged_in?
    end
  end

  it "navigates to the bookmarks page when probing the session" do
    with_tmp_home do
      session = build_session
      page = FakePage.new
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(page)

      session.logged_in?

      assert_equal [Xbookmark::Browser::Session::BOOKMARKS_URL], page.visited
      assert page.closed, "page should be closed after with_page"
    end
  end

  it "yields a fresh page and closes it after the block" do
    with_tmp_home do
      session = build_session
      page = FakePage.new
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(page)

      session.with_page { |p| assert_same page, p }

      assert page.closed, "page should be closed after with_page"
    end
  end

  it "closes the page even when the block raises" do
    with_tmp_home do
      session = build_session
      page = FakePage.new
      FakeFerrumBrowser.any_instance.stubs(:create_page).returns(page)

      assert_raises(RuntimeError) { session.with_page { raise "boom" } }
      assert page.closed
    end
  end

  it "quits and clears the browser" do
    with_tmp_home do
      session = build_session
      browser = session.start
      session.quit
      assert_equal 1, browser.quit_count
      # A second quit is a harmless no-op (browser already cleared).
      session.quit
      assert_equal 1, browser.quit_count
    end
  end

  it "resolves the real Ferrum::Browser class without launching a browser" do
    # Calling the seam requires the gem; merely naming the constant does not
    # spawn Chromium.
    klass = described_class.ferrum_browser_class
    assert_equal "Ferrum::Browser", klass.name
  end
end
