# frozen_string_literal: true

# A test double for the codex headless CLI. Maintains a stack of canned
# JSON responses keyed by an arbitrary tag (or just LIFO order) so each
# call returns the next pre-programmed response.
class FakeCodex
  attr_reader :calls

  def initialize
    @responses = []
    @calls = []
  end

  def push(json)
    @responses << json
    self
  end

  def call(argv, _timeout)
    @calls << argv
    response = @responses.shift
    raise "FakeCodex out of canned responses" if response.nil?
    if response.is_a?(Exception)
      raise response
    elsif response.is_a?(Integer) # exit code
      ["", "fake-codex error", DummyStatus.new(response)]
    else
      [response.is_a?(String) ? response : JSON.generate(response), "", DummyStatus.new(0)]
    end
  end

  DummyStatus = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end
end
