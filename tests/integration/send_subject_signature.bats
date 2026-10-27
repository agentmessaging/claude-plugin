#!/usr/bin/env bats
# =============================================================================
# The signature covers the subject exactly as the envelope stores it
# =============================================================================
#
# amp-send built the signed text with jq @tsv, which escapes a backslash, tab
# and newline. The envelope kept the plain subject, so amp-read / amp-inbox
# (which verify the stored subject) said BAD SIGNATURE on a message that was
# fine. Local delivery also marked every message trust=verified without
# checking anything.

setup() {
    load '../test_helper'
    setup_amp_env
    unset AMP_DIR
    AGENTS="${HOME}/.agent-messaging/agents"
    mkdir -p "${HOME}/agents/alice" "${HOME}/agents/bob"
    mock_curl "000" ""
    for n in alice bob; do
        (cd "${HOME}/agents/$n" && bash "${SCRIPTS_DIR}/amp-init.sh" --name $n --tenant acme >/dev/null 2>&1)
    done
    ALICE=$(jq -r '.alice' "${AGENTS}/.index.json")
    BOB=$(jq -r '.bob' "${AGENTS}/.index.json")
}

send_and_read() {
    local subject="$1"
    cd "${HOME}/agents/alice"
    bash "${SCRIPTS_DIR}/amp-send.sh" --id "$ALICE" bob "$subject" "a message" >/dev/null 2>&1
    MSG_FILE=$(ls "${AGENTS}/${BOB}"/messages/inbox/*/*.json | head -1)
    MSG_ID=$(jq -r '.envelope.id' "$MSG_FILE")
    cd "${HOME}/agents/bob"
    bash "${SCRIPTS_DIR}/amp-read.sh" --id "$BOB" "$MSG_ID" --no-mark-read
}

@test "a plain subject reads as VERIFIED" {
    run send_and_read "Hello there"
    assert_success
    assert_output --partial "VERIFIED"
}

@test "a subject with a backslash reads as VERIFIED" {
    run send_and_read 'RS=\001 and a\b'
    assert_success
    assert_output --partial "VERIFIED"
    refute_output --partial "BAD SIGNATURE"
}

@test "a subject with a tab reads as VERIFIED" {
    run send_and_read $'before\tafter'
    assert_success
    assert_output --partial "VERIFIED"
    refute_output --partial "BAD SIGNATURE"
}

@test "a subject with a newline reads as VERIFIED" {
    run send_and_read $'line one\nline two'
    assert_success
    assert_output --partial "VERIFIED"
    refute_output --partial "BAD SIGNATURE"
}

@test "local delivery records trust=verified only after the signature checked out" {
    send_and_read "Hello there" >/dev/null
    [ "$(jq -r '.local.security.trust' "$MSG_FILE")" = "verified" ]
}
