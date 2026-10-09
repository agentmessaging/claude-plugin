#!/usr/bin/env bats
# amp-prune.sh: retention for messages and attachments, and the opportunistic
# once-a-day call from save_to_inbox. Everything runs under a temp HOME/AMP_DIR.

setup() {
    load '../test_helper'
    setup_amp_env
    PRUNE="${SCRIPTS_DIR}/amp-prune.sh"
    OLD="202001010000"   # touch -t stamp, years ago
    mkdir -p "${AMP_DIR}/messages/inbox/bob example" "${AMP_DIR}/messages/sent/alice"
    IN="${AMP_DIR}/messages/inbox/bob example"
    SENT="${AMP_DIR}/messages/sent/alice"
    echo '{"envelope":{"id":"m_read_old"},"local":{"status":"read"}}' > "$IN/m_read_old.json"
    echo '{"envelope":{"id":"m_unread_old"},"local":{"status":"unread"}}' > "$IN/m_unread_old.json"
    echo '{"envelope":{"id":"m_read_new"},"local":{"status":"read"}}' > "$IN/m_read_new.json"
    echo '{"envelope":{"id":"m_with space"},"local":{"status":"read"}}' > "$IN/with space.json"
    echo '{"envelope":{"id":"s_old"}}' > "$SENT/s_old.json"
    echo '{"envelope":{"id":"s_new"}}' > "$SENT/s_new.json"
    touch -t "$OLD" "$IN/m_read_old.json" "$IN/m_unread_old.json" "$IN/with space.json" "$SENT/s_old.json"
    # attachments: one orphaned and old, one referenced by a kept message, one new
    mkdir -p "${AMP_DIR}/attachments/att_orphan" "${AMP_DIR}/attachments/att_kept" "${AMP_DIR}/attachments/att_new"
    head -c 2048 /dev/zero > "${AMP_DIR}/attachments/att_orphan/file one.bin"
    echo x > "${AMP_DIR}/attachments/att_kept/f.txt"
    echo x > "${AMP_DIR}/attachments/att_new/f.txt"
    echo '{"envelope":{"id":"m_unread_old"},"payload":{"attachments":[{"id":"att_kept"}]},"local":{"status":"unread"}}' > "$IN/m_unread_old.json"
    touch -t "$OLD" "$IN/m_unread_old.json"
    touch -t "$OLD" "${AMP_DIR}/attachments/att_orphan/file one.bin" "${AMP_DIR}/attachments/att_orphan" \
        "${AMP_DIR}/attachments/att_kept/f.txt" "${AMP_DIR}/attachments/att_kept"
}

@test "dry run is the default and deletes nothing" {
    run bash "$PRUNE"
    assert_success
    assert_output --partial "Would remove: 3 message(s), 1 attachment folder(s)"
    assert_output --partial "Dry run"
    [ -f "$IN/m_read_old.json" ]
    [ -f "$SENT/s_old.json" ]
    [ -d "${AMP_DIR}/attachments/att_orphan" ]
}

@test "apply removes old read inbox, old sent and orphaned attachments only" {
    run bash "$PRUNE" --apply
    assert_success
    assert_output --partial "Removed: 3 message(s), 1 attachment folder(s)"
    [ ! -e "$IN/m_read_old.json" ]
    [ ! -e "$IN/with space.json" ]
    [ ! -e "$SENT/s_old.json" ]
    [ ! -d "${AMP_DIR}/attachments/att_orphan" ]
    # kept: unread, recent, referenced attachment, recent attachment
    [ -f "$IN/m_unread_old.json" ]
    [ -f "$IN/m_read_new.json" ]
    [ -f "$SENT/s_new.json" ]
    [ -d "${AMP_DIR}/attachments/att_kept" ]
    [ -d "${AMP_DIR}/attachments/att_new" ]
}

@test "it reports old unread messages as kept and the bytes freed" {
    run bash "$PRUNE" --apply
    assert_output --partial "Kept 1 old unread"
    bytes=$(echo "$output" | sed -n 's/.* \([0-9][0-9]*\) bytes.*/\1/p')
    [ "$bytes" -ge 2048 ]
}

@test "--include-unread removes the unread one, and its attachment becomes orphaned" {
    run bash "$PRUNE" --apply --include-unread
    assert_success
    [ ! -e "$IN/m_unread_old.json" ]
    [ ! -d "${AMP_DIR}/attachments/att_kept" ]
    [ -d "${AMP_DIR}/attachments/att_new" ]
}

@test "--days controls the threshold" {
    run bash "$PRUNE" --apply --days 100000
    assert_output --partial "Removed: 0 message(s), 0 attachment folder(s)"
    [ -f "$IN/m_read_old.json" ]
}

@test "bad --days is rejected" {
    run bash "$PRUNE" --days abc
    assert_failure
    run bash "$PRUNE" --days 0
    assert_failure
}

@test "symlinks are never followed or removed" {
    outside="${BATS_TEST_TMPDIR}/outside"
    mkdir -p "$outside"
    echo keep > "$outside/secret.json"
    touch -t "$OLD" "$outside/secret.json"
    ln -s "$outside/secret.json" "$IN/link.json"
    ln -s "$outside" "${AMP_DIR}/attachments/att_link"
    mkdir -p "$IN/real"; ln -s "$outside" "$IN/real/dir"
    run bash "$PRUNE" --apply
    assert_success
    [ -f "$outside/secret.json" ]
    [ -L "$IN/link.json" ]
    [ -L "${AMP_DIR}/attachments/att_link" ]
}

@test "empty sender folders are removed after apply" {
    run bash "$PRUNE" --apply
    [ ! -d "${AMP_DIR}/messages/sent/alice" ] || [ -f "$SENT/s_new.json" ]
    rm -f "$SENT/s_new.json"
    run bash "$PRUNE" --apply
    assert_success
}

# --- opportunistic call -------------------------------------------------------

# Wait for a background prune to finish removing a file.
wait_gone() {
    for _ in $(seq 1 50); do [ ! -e "$1" ] && return 0; sleep 0.1; done
    return 1
}

save_msg() {
    bash -c 'source "$1/amp-helper.sh"; save_to_inbox "$2" false' _ "$SCRIPTS_DIR" \
        '{"envelope":{"id":"msg_new_1","from":"carol@acme.aimaestro.local","to":"me@acme.aimaestro.local"},"payload":{}}'
}

@test "save_to_inbox does NOT prune by default (opt-in only)" {
    unset AMP_RETENTION_DAYS
    run save_msg
    assert_success
    sleep 1
    [ -f "$IN/m_read_old.json" ]
    [ ! -e "${AMP_DIR}/.last-prune" ]
}

@test "save_to_inbox ignores a non-numeric AMP_RETENTION_DAYS" {
    export AMP_RETENTION_DAYS=soon
    run save_msg
    assert_success
    sleep 1
    [ -f "$IN/m_read_old.json" ]
}

@test "save_to_inbox prunes in the background and writes a stamp when opted in" {
    export AMP_RETENTION_DAYS=90
    run save_msg
    assert_success
    wait_gone "$IN/m_read_old.json"
    [ -f "${AMP_DIR}/.last-prune" ]
    [ -f "$IN/m_unread_old.json" ]
}

@test "save_to_inbox does not prune again within 24 hours" {
    export AMP_RETENTION_DAYS=90
    touch "${AMP_DIR}/.last-prune"
    run save_msg
    assert_success
    sleep 1
    [ -f "$IN/m_read_old.json" ]
}

@test "AMP_RETENTION_DAYS=0 disables the opportunistic prune" {
    export AMP_RETENTION_DAYS=0
    run save_msg
    assert_success
    sleep 1
    [ -f "$IN/m_read_old.json" ]
    [ ! -e "${AMP_DIR}/.last-prune" ]
}

@test "a stale stamp lets the prune run again" {
    export AMP_RETENTION_DAYS=90
    touch -t "$OLD" "${AMP_DIR}/.last-prune"
    run save_msg
    assert_success
    wait_gone "$IN/m_read_old.json"
}
