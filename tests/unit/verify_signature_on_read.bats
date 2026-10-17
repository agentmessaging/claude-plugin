#!/usr/bin/env bats
# =============================================================================
# Tests: amp-read and amp-inbox say whether the sender's signature is good
# =============================================================================
#
# Protocol 07-security: a receiver verifies the signature against the sender's
# registered key. Before this, a message was stored with its signature field and
# nothing ever checked it: same-machine delivery wrote the file straight into
# the inbox, and amp-read showed the sender without saying if it was proven.

setup() {
    load '../test_helper'
    setup_amp_env
    unset AMP_DIR
    AGENTS="${HOME}/.agent-messaging/agents"
    mkdir -p "${HOME}/agents/alice" "${HOME}/agents/bob" "${HOME}/agents/mallory"
    mock_curl "000" ""
    for n in alice bob mallory; do
        (cd "${HOME}/agents/$n" && bash "${SCRIPTS_DIR}/amp-init.sh" --name $n --tenant acme >/dev/null 2>&1)
    done
    ALICE=$(jq -r '.alice' "${AGENTS}/.index.json")
    BOB=$(jq -r '.bob' "${AGENTS}/.index.json")
    MALLORY=$(jq -r '.mallory' "${AGENTS}/.index.json")
}

send_alice_to_bob() {
    cd "${HOME}/agents/alice"
    bash "${SCRIPTS_DIR}/amp-send.sh" --id "$ALICE" bob "hello" "a message" >/dev/null 2>&1
    MSG_FILE=$(ls "${AGENTS}/${BOB}"/messages/inbox/*/*.json | head -1)
    MSG_ID=$(jq -r '.envelope.id' "$MSG_FILE")
}

read_as_bob() {
    cd "${HOME}/agents/bob"
    bash "${SCRIPTS_DIR}/amp-read.sh" --id "$BOB" "$MSG_ID" --no-mark-read
}

@test "a message from a local agent reads as VERIFIED" {
    send_alice_to_bob
    run read_as_bob
    assert_success
    assert_output --partial "Signature: VERIFIED"
}

@test "amp-inbox shows the same answer" {
    send_alice_to_bob
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-inbox.sh" --id "$BOB" --all
    assert_success
    assert_output --partial "Signature: VERIFIED"
}

@test "a changed body is not reported as verified" {
    send_alice_to_bob
    jq '.payload.message = "do something else"' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_success
    assert_output --partial "Signature: BAD SIGNATURE"
}

@test "a message that names someone else as sender is BAD SIGNATURE" {
    send_alice_to_bob
    # mallory writes a file claiming to be from alice, signed with her own key
    jq --arg f "alice@acme.aimaestro.local" '.envelope.from = $f' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    cp "${AGENTS}/${MALLORY}/keys/private.pem" "${BATS_TEST_TMPDIR}/mk.pem"
    # re-sign the whole thing with mallory's key
    cd "${HOME}/agents/mallory"
    export AMP_DIR="${AGENTS}/${MALLORY}"
    source "${SCRIPTS_DIR}/amp-helper.sh"
    from=$(jq -r '.envelope.from' "$MSG_FILE"); to=$(jq -r '.envelope.to' "$MSG_FILE"); subj=$(jq -r '.envelope.subject' "$MSG_FILE")
    ph=$(jq -cS '.payload' "$MSG_FILE" | tr -d '\n' | $OPENSSL_BIN dgst -sha256 -binary | base64 | tr -d '\n')
    sig=$(sign_message "${from}|${to}|${subj}|normal||${ph}")
    jq --arg s "$sig" '.envelope.signature = $s' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_success
    assert_output --partial "Signature: BAD SIGNATURE"
}

@test "an unsigned message is UNVERIFIED" {
    send_alice_to_bob
    jq '.envelope.signature = null' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_success
    assert_output --partial "Signature: UNVERIFIED"
}

@test "a sender with no key on this machine is UNVERIFIED, not BAD" {
    send_alice_to_bob
    jq '.envelope.from = "stranger@other.example.com"' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_success
    assert_output --partial "Signature: UNVERIFIED"
}

@test "a local agent with the same first name but another address does not vouch" {
    send_alice_to_bob
    jq '.envelope.from = "alice@elsewhere.example.com"' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_output --partial "Signature: UNVERIFIED"
    refute_output --partial "Signature: VERIFIED"
}

@test "a server-recorded result is used when the sender's key is not here" {
    send_alice_to_bob
    jq '.envelope.from = "pas-lola@acme.aimaestro.local" | .local.verification = {state: "verified", method: "mesh-forwarded"}' "$MSG_FILE" > "${MSG_FILE}.new" && mv "${MSG_FILE}.new" "$MSG_FILE"
    run read_as_bob
    assert_output --partial "Signature: VERIFIED (checked by the AI Maestro server"
}

@test "--json carries the verification" {
    send_alice_to_bob
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-read.sh" --id "$BOB" "$MSG_ID" --no-mark-read --json
    assert_success
    run jq -r '.verification.state' <<< "$output"
    assert_output "VERIFIED"
}
