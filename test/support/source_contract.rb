# frozen_string_literal: true

# Executable form of the prose source contract documented in
# Xbookmark::Sources::Factory: every bookmark source must expose a `bookmarks`
# that returns an Enumerator when called without a block, and a `get_tweet` that
# NEVER returns nil — a payload (with "data") for a present tweet, and a raised
# SourceUnavailable for a gone one. get_tweet_any in Sync::Runner trusts both
# invariants, so both X::Client and Browser::Source include this module to keep
# the contract enforceable on each implementation, not just asserted in prose.
#
# The including describe must define:
#   build_contract_bookmarks_source -> a source whose #bookmarks can be enumerated
#   build_contract_present_source   -> a source whose get_tweet(present id) resolves
#   build_contract_missing_source   -> a source whose get_tweet(missing id) is gone
#   contract_present_id             -> the id the present source resolves
#   contract_missing_id             -> the id the missing source reports gone
module SourceContractTest
  def self.included(base)
    base.class_eval do
      it "(contract) returns an Enumerator from bookmarks called without a block" do
        assert_kind_of Enumerator, build_contract_bookmarks_source.bookmarks(user_id: "42")
      end

      it "(contract) get_tweet returns a non-nil payload with data for a present tweet" do
        payload = build_contract_present_source.get_tweet(contract_present_id)
        refute_nil payload, "get_tweet must never return nil"
        assert payload["data"], "get_tweet payload must carry data the Runner can expand"
      end

      it "(contract) get_tweet raises SourceUnavailable (never nil) for a gone tweet" do
        assert_raises(Xbookmark::SourceUnavailable) do
          build_contract_missing_source.get_tweet(contract_missing_id)
        end
      end
    end
  end
end
