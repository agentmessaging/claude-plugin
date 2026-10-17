#!/usr/bin/env bats
# One agent, several addresses: one per tenant it registered in (the local network,
# Crabmail, ...), each with its own key. Their mail lands in the one inbox.

setup() {
    load '../test_helper'
    setup_amp_env
    UUID="11111111-2222-3333-4444-555555555555"
    AG="${HOME}/.agent-messaging/agents/${UUID}"
    mkdir -p "${AG}/messages/inbox/crab" "${AG}/registrations"
    cat > "${AG}/config.json" <<JSON
{"agent":{"name":"sebastian","address":"sebastian@rnd23blocks.aimaestro.local","id":"${UUID}"},"address":"sebastian@rnd23blocks.aimaestro.local","provider":{"domain":"aimaestro.local","maestro_url":"http://localhost:23000"}}
JSON
    mkdir -p "${AG}/keys"
    openssl genpkey -algorithm ed25519 -out "${AG}/keys/private.pem" 2>/dev/null
    openssl pkey -in "${AG}/keys/private.pem" -pubout -out "${AG}/keys/public.pem" 2>/dev/null
    export AMP_AGENT_ID="$UUID"
    DIR="${HOME}/work"; mkdir -p "$DIR"
}

line1() {
    printf '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":20000},"cost":{"total_cost_usd":0.5},"workspace":{"current_dir":"%s"}}' "$DIR" \
        | COLUMNS=200 bash "${SCRIPTS_DIR}/amp-statusline.sh" | head -1
}

msg_to() {
    cat > "${AG}/messages/inbox/crab/msg_1_a.json" <<JSON
{"envelope":{"id":"msg_1_a","from":"alice@acme.crabmail.ai","to":"$1","subject":"hi","priority":"normal","timestamp":"2026-10-17T00:00:00Z"},"payload":{"type":"notification","message":"x"},"local":{"status":"unread"}}
JSON
}

@test "one address: the status line is unchanged" {
    run line1
    assert_output "sebastian · sebastian@rnd23blocks.aimaestro.local · ~/work | 0 unread"
}

@test "the registration for the main address is not counted as another identity" {
    echo '{"provider":"rnd23blocks.aimaestro.local","address":"Sebastian@rnd23blocks.aimaestro.local"}' > "${AG}/registrations/rnd23blocks.aimaestro.local.json"
    run line1
    assert_output "sebastian · sebastian@rnd23blocks.aimaestro.local · ~/work | 0 unread"
}

@test "another tenant's registration shows as +1" {
    echo '{"provider":"crabmail.ai","address":"sebastian@23blocks.crabmail.ai"}' > "${AG}/registrations/crabmail.ai.json"
    run line1
    assert_output "sebastian · sebastian@rnd23blocks.aimaestro.local +1 · ~/work | 0 unread"
}

@test "mail sent to the other address counts as unread in the same bar" {
    echo '{"provider":"crabmail.ai","address":"sebastian@23blocks.crabmail.ai"}' > "${AG}/registrations/crabmail.ai.json"
    msg_to "sebastian@23blocks.crabmail.ai"
    run line1
    assert_output --partial "+1"
    assert_output --partial "1 unread"
}

@test "amp-inbox says which address a message was sent to when it is not the main one" {
    msg_to "sebastian@23blocks.crabmail.ai"
    run env AMP_DIR="$AG" bash "${SCRIPTS_DIR}/amp-inbox.sh"
    assert_success
    assert_output --partial "To: sebastian@23blocks.crabmail.ai"
}

@test "amp-inbox stays quiet about To: for the main address" {
    msg_to "sebastian@rnd23blocks.aimaestro.local"
    run env AMP_DIR="$AG" bash "${SCRIPTS_DIR}/amp-inbox.sh"
    assert_success
    refute_output --partial "To: "
}
