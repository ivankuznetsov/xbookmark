# frozen_string_literal: true

require "xbookmark/media/downloader"
require "xbookmark/x/bookmark"

RSpec.describe Xbookmark::Media::Downloader do
  let(:photo) do
    Xbookmark::X::Media.new(media_key: "m1", type: "photo", url: "https://x/img.jpg",
                            variants: [], duration_ms: nil)
  end

  let(:video) do
    Xbookmark::X::Media.new(
      media_key: "v1", type: "video",
      variants: [
        { "bit_rate" => 320_000, "content_type" => "video/mp4", "url" => "https://x/low.mp4" },
        { "bit_rate" => 832_000, "content_type" => "video/mp4", "url" => "https://x/hi.mp4" },
        { "content_type" => "application/x-mpegURL", "url" => "https://x/playlist.m3u8" }
      ],
      duration_ms: 10_000
    )
  end

  it "downloads an image to the destination directory" do
    Dir.mktmpdir do |dir|
      stub = ->(_) { "imagebytes" }
      records = described_class.new(http: stub).download([photo], dir)
      expect(records.size).to eq(1)
      expect(File.read(records.first[:path])).to eq("imagebytes")
      expect(records.first[:kind]).to eq("photo")
    end
  end

  it "picks the highest-bitrate mp4 variant for a video" do
    Dir.mktmpdir do |dir|
      seen = []
      stub = ->(url) { seen << url; "videobytes" }
      records = described_class.new(http: stub).download([video], dir)
      expect(seen).to eq(["https://x/hi.mp4"])
      expect(records.first[:kind]).to eq("video")
    end
  end

  it "uniquifies filenames when two media share a basename" do
    media_a = Xbookmark::X::Media.new(media_key: "a", type: "photo", url: "https://x/foo/img.jpg", variants: [])
    media_b = Xbookmark::X::Media.new(media_key: "b", type: "photo", url: "https://x/bar/img.jpg", variants: [])
    Dir.mktmpdir do |dir|
      stub = ->(url) { "bytes-#{url}" }
      records = described_class.new(http: stub).download([media_a, media_b], dir)
      expect(records.map { |r| r[:path] }.uniq.size).to eq(2)
    end
  end

  it "raises MediaError on a Down failure" do
    bad = Xbookmark::X::Media.new(media_key: "x", type: "photo", url: "https://x/missing.jpg", variants: [])
    Dir.mktmpdir do |dir|
      stub_request(:get, "https://x/missing.jpg").to_return(status: 404)
      expect { described_class.new.download([bad], dir) }.to raise_error(Xbookmark::MediaError)
    end
  end
end
