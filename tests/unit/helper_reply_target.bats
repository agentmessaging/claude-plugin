#!/usr/bin/env bats
# =============================================================================
# Tests: reply-target safety — record_last_read / get_last_read_id /
#        get_last_read_from
#
# Guards against the production misroute where
#     amp-reply "$(amp-inbox | head -1)" "..."
# aimed a reply at whatever was top of the inbox rather than the message being
# answered, sending one company's internal detail into another agent's mailbox.
# The invariant enforced by amp-reply is "you reply to the message you just
# read"; these cover the state it reads to decide.
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
    source_amp_helper
}

@test "get_last_read_id: empty before anything is read" {
    [ -z "$(get_last_read_id)" ]
}

@test "record_last_read: id round-trips" {
    record_last_read "msg_1000_aa" "alice@testorg.aimaestro.local"
    [ "$(get_last_read_id)" = "msg_1000_aa" ]
}

@test "record_last_read: sender round-trips" {
    record_last_read "msg_1000_aa" "alice@testorg.aimaestro.local"
    [ "$(get_last_read_from)" = "alice@testorg.aimaestro.local" ]
}

@test "record_last_read: the most recent read wins" {
    # The invariant is LAST read, singular — reading B after A means a reply must
    # target B, which is exactly what catches read-A-then-reply-to-top-of-inbox.
    record_last_read "msg_1000_aa" "alice@testorg.aimaestro.local"
    record_last_read "msg_2000_bb" "bob@testorg.aimaestro.local"
    [ "$(get_last_read_id)" = "msg_2000_bb" ]
    [ "$(get_last_read_from)" = "bob@testorg.aimaestro.local" ]
}

@test "record_last_read: empty id is a no-op, not a corrupt marker" {
    record_last_read "msg_1000_aa" "alice@testorg.aimaestro.local"
    record_last_read "" ""
    [ "$(get_last_read_id)" = "msg_1000_aa" ]
}

@test "the marker is per-agent, under AMP_DIR" {
    record_last_read "msg_1000_aa" "alice@testorg.aimaestro.local"
    # The file lives inside this agent's dir, so another agent cannot read it.
    run bash -c "ls ${AMP_DIR}/.last-read-* 2>/dev/null"
    assert_success
}

@test "the mismatch decision: target differs from last read" {
    # The exact comparison amp-reply makes before refusing.
    record_last_read "msg_READ_x" "bob@testorg.aimaestro.local"
    local target="msg_TOP_y"   # what head -1 would have handed us
    local last; last="$(get_last_read_id)"
    [ -n "$last" ]
    [ "$last" != "$target" ]   # → amp-reply refuses without --force
}

@test "the match decision: replying to what you read is allowed" {
    record_last_read "msg_READ_x" "bob@testorg.aimaestro.local"
    local target="msg_READ_x"
    [ "$(get_last_read_id)" = "$target" ]   # → amp-reply proceeds
}
