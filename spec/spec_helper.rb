# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "tempfile"
require "json"
require "webmock/rspec"

ENV["XBOOKMARK_TEST"] = "1"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "xbookmark"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before(:each) do
    @__test_envs__ = {}
    %w[
      XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
      X_CLIENT_ID X_CLIENT_SECRET X_REDIRECT_URI
      X_USER_ID X_ACCESS_TOKEN X_REFRESH_TOKEN X_TOKEN_EXPIRES_AT
      XBOOKMARK_WIKI_PATH XBOOKMARK_VAULT OBSIDIAN_VAULT_PATH
      XBOOKMARK_LOGS_DIR XBOOKMARK_DAILY_TIME
      XBOOKMARK_MIN_RUN_INTERVAL_HOURS
      CODEX_BIN WHISPER_BIN WHISPER_MODEL QMD_BIN
    ].each { |k| @__test_envs__[k] = ENV[k]; ENV.delete(k) }
  end

  config.after(:each) do
    @__test_envs__.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v } if @__test_envs__
  end

  WebMock.disable_net_connect!(allow_localhost: true)
end

module SpecSupport
  def with_tmp_home
    Dir.mktmpdir("xbookmark-home") do |home|
      orig_home = ENV["HOME"]
      ENV["HOME"] = home
      begin
        yield home
      ensure
        ENV["HOME"] = orig_home
      end
    end
  end

  def stub_platform_linux
    allow(Xbookmark::Paths).to receive(:macos?).and_return(false)
    allow(Xbookmark::Paths).to receive(:linux?).and_return(true)
  end

  def stub_platform_macos
    allow(Xbookmark::Paths).to receive(:macos?).and_return(true)
    allow(Xbookmark::Paths).to receive(:linux?).and_return(false)
  end
end

RSpec.configure { |c| c.include SpecSupport }
