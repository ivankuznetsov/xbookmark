# frozen_string_literal: true

require "open3"
require "json"
require "json-schema"

module Xbookmark
  module Enrich
    # Thin wrapper around the codex headless CLI. Builds argv, captures
    # stdout/stderr, parses JSON, validates against an optional schema, and
    # surfaces failures as Xbookmark::CodexError.
    class Codex
      DEFAULT_TIMEOUT = 120

      attr_reader :bin

      def initialize(bin: "codex", runner: nil)
        @bin = bin
        @runner = runner
      end

      # prompt: String. images: Array of paths. json_schema: optional schema
      # for validation. Returns parsed JSON, or raw string when no schema.
      def run(prompt:, images: [], json_schema: nil, timeout: DEFAULT_TIMEOUT, extra_argv: [])
        argv = build_argv(prompt: prompt, images: images, extra_argv: extra_argv)

        out, err, status = invoke(argv, timeout: timeout)
        unless status_success?(status)
          raise Xbookmark::CodexError, "codex exited #{status_exit(status)}: #{err}"
        end

        if json_schema
          parsed = parse_json!(out)
          errors = JSON::Validator.fully_validate(json_schema, parsed)
          raise Xbookmark::CodexError, "codex output failed schema validation: #{errors.join("; ")}" if errors.any?
          parsed
        else
          out
        end
      end

      def build_argv(prompt:, images:, extra_argv:)
        argv = [@bin, "exec", "--json"]
        Array(images).each { |p| argv.push("--image", p.to_s) }
        argv.concat(extra_argv) if extra_argv && !extra_argv.empty?
        argv.push("--", prompt)
        argv
      end

      private

      def invoke(argv, timeout:)
        if @runner
          return @runner.call(argv, timeout)
        end
        out, err, status = Open3.capture3(*argv)
        [out, err, status]
      end

      def parse_json!(raw)
        # codex --json prints structured events; we accept either a single
        # JSON object on stdout or a stream of newline-delimited events
        # whose `message_complete` carries the body. Keep it simple here:
        # try to find the last well-formed JSON object in the output.
        candidate = raw.strip
        return JSON.parse(candidate) if candidate.start_with?("{")
        candidate = candidate.lines.reverse.find { |l| l.strip.start_with?("{") }
        raise Xbookmark::CodexError, "codex stdout was not JSON: #{raw[0, 200]}" unless candidate
        JSON.parse(candidate)
      rescue JSON::ParserError => e
        raise Xbookmark::CodexError, "codex stdout JSON parse failed: #{e.message}"
      end

      def status_success?(status)
        status.respond_to?(:success?) ? status.success? : status == 0
      end

      def status_exit(status)
        status.respond_to?(:exitstatus) ? status.exitstatus : status
      end
    end
  end
end
