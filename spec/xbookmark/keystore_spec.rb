# frozen_string_literal: true

require "xbookmark/keystore"
require "xbookmark/keystore/importer"

RSpec.describe Xbookmark::Keystore do
  let(:memory) { Xbookmark::Keystore::Memory.new }

  describe "facade" do
    it "round-trips set/get/delete via the memory backend" do
      ks = described_class.new(backend: memory)
      expect(ks.get("X_CLIENT_ID")).to be_nil
      ks.set("X_CLIENT_ID", "abc")
      expect(ks.get("X_CLIENT_ID")).to eq("abc")
      ks.delete("X_CLIENT_ID")
      expect(ks.get("X_CLIENT_ID")).to be_nil
    end

    it "normalises env-style keys to lowercase account names" do
      ks = described_class.new(backend: memory)
      ks.set("X_USER_ID", "42")
      expect(memory.get("x_user_id")).to eq("42")
    end

    it "delete_all removes only known keys that exist" do
      ks = described_class.new(backend: memory)
      ks.set("X_CLIENT_ID", "abc")
      ks.set("X_USER_ID", "42")
      ks.set("X_UNKNOWN", "nope") # not in KNOWN_KEYS, ignored
      removed = ks.delete_all
      expect(removed).to contain_exactly("x_client_id", "x_user_id")
      expect(ks.get("X_CLIENT_ID")).to be_nil
      expect(ks.get("X_USER_ID")).to be_nil
    end

    it "hydrate fills missing env keys without clobbering present ones" do
      ks = described_class.new(backend: memory)
      ks.set("X_CLIENT_ID", "from-keystore")
      env = { "X_USER_ID" => "from-env" }
      ks.hydrate(env)
      expect(env["X_CLIENT_ID"]).to eq("from-keystore")
      expect(env["X_USER_ID"]).to eq("from-env")
    end
  end

  describe "backend selection" do
    it "picks Keychain on macOS" do
      stub_platform_macos
      ks = described_class.new
      expect(ks.backend).to be_a(Xbookmark::Keystore::Keychain)
    end

    it "falls back to EnvFile on Linux when secret-tool / DBUS unavailable" do
      stub_platform_linux
      ENV.delete("DBUS_SESSION_BUS_ADDRESS")
      allow(Xbookmark::Keystore::Libsecret).to receive(:available?).and_return(false)
      ks = described_class.new
      expect(ks.backend).to be_a(Xbookmark::Keystore::EnvFile)
    end

    it "picks Libsecret on Linux when secret-tool + DBUS are present" do
      stub_platform_linux
      ENV["DBUS_SESSION_BUS_ADDRESS"] = "/run/user/1000/bus"
      allow(Xbookmark::Keystore::Libsecret).to receive(:available?).and_return(true)
      ks = described_class.new
      expect(ks.backend).to be_a(Xbookmark::Keystore::Libsecret)
    ensure
      ENV.delete("DBUS_SESSION_BUS_ADDRESS")
    end
  end
end

RSpec.describe Xbookmark::Keystore::Libsecret do
  let(:backend) { described_class.new }

  it "shells out to `secret-tool lookup` for get" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "secret-tool", "lookup",
      "service", "xbookmark",
      "account", "x_client_id"
    ).and_return(["abc\n", "", status])

    expect(backend.get("x_client_id")).to eq("abc\n")
  end

  it "returns nil when secret-tool exits non-zero" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "", status])
    expect(backend.get("missing")).to be_nil
  end

  it "passes value via stdin to secret-tool store" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "secret-tool", "store",
      "--label=xbookmark",
      "service", "xbookmark",
      "account", "x_client_id",
      stdin_data: "secret"
    ).and_return(["", "", status])

    backend.set("x_client_id", "secret")
  end
end

RSpec.describe Xbookmark::Keystore::Keychain do
  let(:backend) { described_class.new }

  it "shells out to `security find-generic-password` for get" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "security", "find-generic-password",
      "-s", "xbookmark", "-a", "x_client_id", "-w"
    ).and_return(["abc\n", "", status])

    expect(backend.get("x_client_id")).to eq("abc")
  end
end

RSpec.describe Xbookmark::Keystore::EnvFile do
  it "round-trips set/get/delete and writes with mode 0600" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      backend = described_class.new(path: path)
      backend.set("x_client_id", "abc")
      expect(backend.get("x_client_id")).to eq("abc")
      expect(File.read(path)).to include("X_CLIENT_ID=abc")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      backend.delete("x_client_id")
      expect(backend.get("x_client_id")).to be_nil
    end
  end

  it "lists accounts present in the file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      File.write(path, "X_CLIENT_ID=abc\nX_USER_ID=42\n")
      backend = described_class.new(path: path)
      expect(backend.list_accounts).to contain_exactly("x_client_id", "x_user_id")
    end
  end

  it "round-trips values containing inner double quotes without backslash accumulation" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      backend = described_class.new(path: path)
      secret = %q(s"e"cret)

      backend.set(:x_client_secret, secret)
      expect(backend.get(:x_client_secret)).to eq(secret)

      # Re-write the same value and confirm it still reads back identical —
      # this catches a writer that escapes on every set but a reader that
      # never unescapes (each round adds one backslash).
      backend.set(:x_client_secret, backend.get(:x_client_secret))
      expect(backend.get(:x_client_secret)).to eq(secret)
    end
  end
end

RSpec.describe Xbookmark::Keystore::Importer do
  it "writes every known key from a fixture .env into the keystore" do
    Dir.mktmpdir do |dir|
      env_path = File.join(dir, ".env")
      File.write(env_path, "X_CLIENT_ID=abc\nX_USER_ID=42\nUNUSED=bar\n")
      ks = Xbookmark::Keystore.new(backend: Xbookmark::Keystore::Memory.new)
      migrated = described_class.new(keystore: ks).import(env_path)
      expect(migrated).to contain_exactly("X_CLIENT_ID", "X_USER_ID")
      expect(ks.get("X_CLIENT_ID")).to eq("abc")
      expect(ks.get("X_USER_ID")).to eq("42")
      expect(File.file?(env_path)).to be true # never deletes the source
    end
  end
end
