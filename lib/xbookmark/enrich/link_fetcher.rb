# frozen_string_literal: true

require "faraday"
require "nokogiri"
require "ipaddr"
require "resolv"
require "time"
require "uri"

module Xbookmark
  module Enrich
    class LinkFetcher
      ALLOWED_SCHEMES = %w[http https].freeze

      # Aggregated set of CIDR ranges that must never be reachable from a
      # link fetched on the user's machine — loopback, RFC1918 private
      # networks, link-local (covers AWS/GCE 169.254.169.254 metadata
      # endpoints), and the IPv6 equivalents.
      PRIVATE_RANGES = [
        "0.0.0.0/8",          # current network
        "10.0.0.0/8",         # RFC 1918
        "100.64.0.0/10",      # CGNAT
        "127.0.0.0/8",        # loopback
        "169.254.0.0/16",     # link-local + cloud metadata
        "172.16.0.0/12",      # RFC 1918
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.168.0.0/16",     # RFC 1918
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",        # multicast
        "240.0.0.0/4",        # reserved
        "::1/128",            # IPv6 loopback
        "fc00::/7",           # IPv6 unique local
        "fe80::/10",          # IPv6 link-local
        "ff00::/8"            # IPv6 multicast
      ].map { |c| IPAddr.new(c) }.freeze

      def initialize(conn: nil)
        @conn = conn
      end

      # Returns { url:, final_url:, title:, byline:, text:, fetched_at: } or
      # nil when fetch fails or the URL targets a non-public address.
      def fetch(url)
        return nil unless safe_url?(url)
        res = http.get(url) { |req| req.options.timeout = 20 }
        return nil unless res.success?
        return nil unless safe_url?(res.env.url.to_s)
        doc = Nokogiri::HTML(res.body)
        title = doc.at("title")&.text&.strip
        byline = doc.at('meta[name="author"]')&.[]("content")
        body_nodes = doc.css("article p, main p, p")
        text = body_nodes.map(&:text).join("\n\n").strip[0, 8000]
        {
          url: url,
          final_url: res.env.url.to_s,
          title: title,
          byline: byline,
          text: text,
          fetched_at: Time.now.utc.iso8601
        }
      rescue StandardError
        nil
      end

      def safe_url?(url)
        uri = URI.parse(url.to_s)
        return false unless ALLOWED_SCHEMES.include?(uri.scheme)
        host = uri.host
        return false if host.nil? || host.empty?

        addrs = resolve(host)
        return false if addrs.empty?
        addrs.none? { |addr| private_address?(addr) }
      rescue URI::InvalidURIError
        false
      end

      private

      def resolve(host)
        # Accept literal IPs without DNS, otherwise resolve A and AAAA.
        IPAddr.new(host) # raises on hostname
        [host]
      rescue IPAddr::InvalidAddressError
        begin
          Resolv.getaddresses(host)
        rescue StandardError
          []
        end
      end

      def private_address?(addr_or_host)
        ip = IPAddr.new(addr_or_host.to_s)
        PRIVATE_RANGES.any? { |range| range.include?(ip) }
      rescue StandardError
        # Anything we can't classify is treated as unsafe — fail closed.
        true
      end

      def http
        @conn ||= Faraday.new do |f|
          f.headers["User-Agent"] = "xbookmark/1.0 (link-readability-fetcher)"
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
