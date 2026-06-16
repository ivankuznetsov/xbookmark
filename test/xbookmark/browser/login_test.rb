# frozen_string_literal: true

require "test_helper"
require "xbookmark/browser/login"
require "xbookmark/state/store"

class FakeLoginSession
  attr_reader :opened, :quits, :login_checks

  def initialize(login_results)
    @login_results = login_results
    @opened = []
    @quits = 0
    @login_checks = 0
  end

  def open_page(url) = @opened << url
  def profile_dir = "/tmp/xbookmark-profile"

  def logged_in?
    @login_checks += 1
    @login_results.shift || false
  end

  def quit = @quits += 1
end

describe Xbookmark::Browser::Login do
  let(:config) { Struct.new(:vault_path).new("/tmp/wiki") }
  let(:store) { Xbookmark::State::Store.new(":memory:") }
  let(:clock) { Struct.new(:now).new(Time.at(1_700_000_000)) }

  def build(session, input: "y\n")
    described_class.new(config: config, store: store, session: session,
                        input: StringIO.new(input), output: @out = StringIO.new,
                        clock: clock, sleeper: ->(_) { })
  end

  it "shows the one-time consent warning, logs in, and records consent" do
    session = FakeLoginSession.new([true])
    login = build(session, input: "y\n")

    assert login.call
    assert_includes @out.string, "Browser bookmark source"
    assert_includes @out.string, "Terms of Service"
    assert_includes @out.string, "Browser session saved"
    assert_equal [Xbookmark::Browser::Session::BOOKMARKS_URL], session.opened
    assert_equal 1, session.quits
    refute_nil store.get_meta("browser_consent_at")
  end

  it "suppresses the consent prompt on subsequent runs" do
    store.set_meta("browser_consent_at", "2026-01-01T00:00:00Z")
    session = FakeLoginSession.new([true])
    login = build(session, input: "")

    assert login.call
    refute_includes @out.string, "Browser bookmark source"
  end

  it "aborts without opening a browser when consent is declined" do
    session = FakeLoginSession.new([true])
    login = build(session, input: "n\n")

    refute login.call
    assert_includes @out.string, "Consent declined"
    assert_empty session.opened
    assert_nil store.get_meta("browser_consent_at")
    assert_equal 1, session.quits
  end

  it "polls until the session becomes authenticated" do
    session = FakeLoginSession.new([false, false, true])
    login = build(session)

    assert login.call
    assert_equal 3, session.login_checks
  end

  it "reports a timeout when login is never detected" do
    session = FakeLoginSession.new([])
    login = build(session)

    refute login.call
    assert_includes @out.string, "Login not detected"
    assert_equal 1, session.quits
  end

  it "defaults to a real headless-false Session when none is injected" do
    Xbookmark::Browser::Session.expects(:new).with(config: config, headless: false).returns(FakeLoginSession.new([true]))
    login = described_class.new(config: config, store: store, input: StringIO.new("y\n"),
                                output: StringIO.new, clock: clock, sleeper: ->(_) { })
    assert login.call
  end

  it "uses a real sleep as the default pause between polls" do
    # sleep(0) returns immediately; this just exercises the default sleeper.
    assert_equal 0, described_class::DEFAULT_SLEEPER.call(0)
  end
end
