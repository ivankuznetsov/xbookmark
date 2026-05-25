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

    it "returns a copy of memory backend values" do
      memory.set("x_client_id", "abc")
      copy = memory.to_h
      copy["x_client_id"] = "changed"

      expect(memory.get("x_client_id")).to eq("abc")
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

  it "reports its backend name" do
    expect(backend.name).to eq("libsecret")
  end

  it "detects secret-tool on PATH" do
    Dir.mktmpdir do |dir|
      tool = File.join(dir, "secret-tool")
      File.write(tool, "#!/bin/sh\n")
      File.chmod(0o755, tool)
      stub_const("ENV", ENV.to_hash.merge("PATH" => dir))

      expect(described_class.available?).to be(true)
      expect(described_class.which("missing")).to be_nil
    end
  end

  it "shells out to `secret-tool lookup` for get" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "secret-tool", "lookup",
      "service", "xbookmark",
      "account", "x_client_id"
    ).and_return(["abc\n", "", status])

    expect(backend.get("x_client_id")).to eq("abc\n")
  end

  it "returns nil when secret-tool lookup succeeds with an empty value" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(["", "", status])

    expect(backend.get("empty")).to be_nil
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

  it "raises when secret-tool store fails" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "denied", status])

    expect { backend.set("x_client_id", "secret") }.to raise_error(Xbookmark::Error, /denied/)
  end

  it "deletes and lists accounts through secret-tool" do
    delete_status = instance_double(Process::Status, success?: true)
    list_status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "secret-tool", "clear",
      "service", "xbookmark",
      "account", "x_client_id"
    ).and_return(["", "", delete_status])
    expect(Open3).to receive(:capture3).with(
      "secret-tool", "search", "--all",
      "service", "xbookmark"
    ).and_return(["attribute.account = x_client_id\nattribute.account = x_user_id\n", "", list_status])

    expect(backend.delete("x_client_id")).to be(true)
    expect(backend.list_accounts).to contain_exactly("x_client_id", "x_user_id")
  end

  it "returns an empty account list when secret-tool search fails" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "", status])

    expect(backend.list_accounts).to eq([])
  end
end

RSpec.describe Xbookmark::Keystore::Keychain do
  let(:backend) { described_class.new }

  it "reports its backend name" do
    expect(backend.name).to eq("keychain")
  end

  it "shells out to `security find-generic-password` for get" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "security", "find-generic-password",
      "-s", "xbookmark", "-a", "x_client_id", "-w"
    ).and_return(["abc\n", "", status])

    expect(backend.get("x_client_id")).to eq("abc")
  end

  it "returns nil for missing or empty keychain entries" do
    missing = instance_double(Process::Status, success?: false)
    empty = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(["", "", missing], ["\n", "", empty])

    expect(backend.get("missing")).to be_nil
    expect(backend.get("empty")).to be_nil
  end

  it "adds, deletes, and lists keychain entries" do
    status = instance_double(Process::Status, success?: true)
    expect(Open3).to receive(:capture3).with(
      "security", "add-generic-password",
      "-s", "xbookmark",
      "-a", "x_client_id",
      "-w", "secret",
      "-U"
    ).and_return(["", "", status])
    expect(Open3).to receive(:capture3).with(
      "security", "delete-generic-password",
      "-s", "xbookmark", "-a", "x_client_id"
    ).and_return(["", "", status])

    expect(backend.set("x_client_id", "secret")).to be(true)
    expect(backend.delete("x_client_id")).to be(true)

    allow(backend).to receive(:get) { |account| account == "x_client_id" ? "secret" : nil }
    expect(backend.list_accounts).to eq(["x_client_id"])
  end

  it "raises when adding a keychain entry fails" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "denied", status])

    expect { backend.set("x_client_id", "secret") }.to raise_error(Xbookmark::Error, /denied/)
  end
end

RSpec.describe Xbookmark::Keystore::EnvFile do
  it "reports its backend name with the env file path" do
    backend = described_class.new(path: "/tmp/xbookmark.env")

    expect(backend.name).to eq("env_file (/tmp/xbookmark.env)")
  end

  it "returns nil and no accounts when the file is absent" do
    Dir.mktmpdir do |dir|
      backend = described_class.new(path: File.join(dir, ".env"))

      expect(backend.get("x_client_id")).to be_nil
      expect(backend.list_accounts).to eq([])
    end
  end

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
