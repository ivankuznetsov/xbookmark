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

      # Wrapper events emitted by `codex exec --json`. The model body is
      # carried separately (either as a `model_message`/`agent_message`
      # event or as a plain JSON object without a wrapper type).
      WRAPPER_EVENT_TYPES = %w[
        turn_start turn_end telemetry start progress event finish
        thread.started turn.started turn.completed
        thinking agent_reasoning tool_call tool_result
      ].freeze

      MODEL_MESSAGE_TYPES = %w[model_message agent_message item.completed].freeze

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
          if errors.any?
            # Schema mismatch is not transient — the model consistently
            # produces the wrong shape. Raise PermanentError so the
            # pipeline doesn't burn retry budget on it.
            raise Xbookmark::PermanentError, "codex output failed schema validation: #{errors.join("; ")}"
          end
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
        return @runner.call(argv, timeout) if @runner
        invoke_with_timeout(argv, timeout)
      end

      def invoke_with_timeout(argv, timeout)
        Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }

          if wait_thr.join(timeout).nil?
            pid = wait_thr.pid
            kill_subprocess(pid, wait_thr)
            raise Xbookmark::CodexError, "codex exceeded timeout of #{timeout}s"
          end

          [out_reader.value, err_reader.value, wait_thr.value]
        end
      end

      def kill_subprocess(pid, wait_thr)
        Process.kill("TERM", pid) rescue nil
        50.times do
          break unless wait_thr.alive?
          sleep 0.1
        end
        Process.kill("KILL", pid) rescue nil if wait_thr.alive?
        wait_thr.join
      end

      def parse_json!(raw)
        events = []
        raw.each_line do |line|
          stripped = line.strip
          next if stripped.empty? || !stripped.start_with?("{")
          begin
            events << JSON.parse(stripped)
          rescue JSON::ParserError
            next
          end
        end

        # `codex exec --json` emits typed event envelopes. Skip well-known
        # wrapper types (turn_start, turn_end, telemetry, ...) and return
        # the model body — either a plain JSON object without a wrapper
        # type, or the unwrapped content of a model_message/agent_message
        # envelope.
        events.reverse_each do |event|
          next unless event.is_a?(Hash)
          type = (event["type"] || event["event"]).to_s

          next if WRAPPER_EVENT_TYPES.include?(type)

          if MODEL_MESSAGE_TYPES.include?(type)
            inner = model_message_payload(event)
            return inner if inner.is_a?(Hash)
            if inner.is_a?(String) && inner.strip.start_with?("{")
              parsed_inner = JSON.parse(inner) rescue nil
              return parsed_inner if parsed_inner.is_a?(Hash)
            end
            next
          end

          # No wrapper type — this event is the model body itself.
          return event if type.empty?
        end

        candidate = raw.strip
        return JSON.parse(candidate) if candidate.start_with?("{")
        raise Xbookmark::CodexError, "codex stdout was not JSON: #{raw[0, 200]}"
      rescue JSON::ParserError => e
        # Reached only by the fallback `JSON.parse(candidate)` above.
        raise Xbookmark::CodexError, "codex stdout JSON parse failed: #{e.message}"
      end

      def model_message_payload(event)
        if event["item"].is_a?(Hash)
          item = event["item"]
          return item["text"] if item["type"].to_s == "agent_message"
          return item["content"] || item["message"] || item["body"]
        end

        event["content"] || event["message"] || event["body"] || event["text"]
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
