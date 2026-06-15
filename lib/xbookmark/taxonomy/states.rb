# frozen_string_literal: true

module Xbookmark
  module Taxonomy
    # Canonical taxonomy state vocabulary shared by Report (run-level state and
    # exit codes), Auditor/Rebuilder, and Curator (per-concept curation
    # outcome). Keeping the strings in one place prevents the singular/plural
    # drift that previously let the curator emit "blocked_conflict" while
    # Report only ever recognized "blocked_conflicts".
    module States
      CLEAN = "clean"
      PROPOSED_CHANGES = "proposed_changes"
      BLOCKED_CONFLICTS = "blocked_conflicts"
      APPLIED = "applied"
      PARTIAL_FAILURE = "partial_failure"

      EXIT_CODES = {
        CLEAN => 0,
        PROPOSED_CHANGES => 1,
        BLOCKED_CONFLICTS => 2,
        APPLIED => 0,
        PARTIAL_FAILURE => 3
      }.freeze
    end
  end
end
