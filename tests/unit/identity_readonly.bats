#!/usr/bin/env bats
# =============================================================================
# Tests: a read path must never rewrite the identity it reads
# =============================================================================
#
# Reported from production (3Metas, ~50 agents): `amp-inbox --id <other-agent>`
# run from inside an agent session rewrote the TARGET's config to the CALLER's
# name and dropped the target's id.
#
# Two independent defects combined:
#
#   1. --id was ignored whenever AMP_DIR was already exported (AI Maestro
#      exports it into every agent session), so you silently read your own
#      mailbox believing it was someone else's.
#   2. When --id did take effect, load_config() treated CLAUDE_AGENT_NAME —
#      the CALLER's name — as authoritative for whatever directory happened to
#      be open, "auto-fixed" the mismatch, and called save_config with three
#      arguments, omitting agent_id.
#
# The blast radius scaled with diligence: a manager sweeping the fleet to check
# for identity corruption would have renamed every agent it inspected. The
# audit was the payload.

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
    # Give the config an id, so we can prove repairs preserve it
    jq '.agent.id = "11111111-2222-3333-4444-555555555555"' "${AMP_DIR}/config.json" > "${AMP_DIR}/config.tmp"
    mv "${AMP_DIR}/config.tmp" "${AMP_DIR}/config.json"
    source_amp_helper
}

# --- load_config is read-only ------------------------------------------------

@test "load_config: does NOT rewrite the config on a name mismatch" {
    local before after
    before=$(cat "${AMP_DIR}/config.json")

    CLAUDE_AGENT_NAME="someone-else" load_config

    after=$(cat "${AMP_DIR}/config.json")
    [ "$before" = "$after" ]
}

@test "load_config: reports the mismatch instead of silently fixing it" {
    run env CLAUDE_AGENT_NAME="someone-else" bash -c "source '${SCRIPTS_DIR}/amp-helper.sh'; load_config"
    assert_output --partial "AMP config mismatch"
    assert_output --partial "must not rewrite identity"
}

@test "load_config: leaves the agent id intact on a mismatch" {
    CLAUDE_AGENT_NAME="someone-else" load_config
    run jq -r '.agent.id' "${AMP_DIR}/config.json"
    assert_output "11111111-2222-3333-4444-555555555555"
}

@test "load_config: a mismatch does not stop the config being usable" {
    CLAUDE_AGENT_NAME="someone-else" load_config
    # The real name is still what the config says — not the caller's.
    [ "$AMP_AGENT_NAME" = "testagent" ]
}

# --- explicit repair still works, and preserves the id ------------------------

@test "load_config: repairs only when repair is the declared intent" {
    AMP_ALLOW_CONFIG_REPAIR=1 CLAUDE_AGENT_NAME="renamed-agent" load_config
    run jq -r '.agent.name' "${AMP_DIR}/config.json"
    assert_output "renamed-agent"
}

@test "load_config: an explicit repair preserves the agent id" {
    # This is the half that made the old auto-fix destructive rather than
    # merely wrong: save_config was called with three arguments, so the
    # {id: ...} branch never fired and the id was dropped.
    AMP_ALLOW_CONFIG_REPAIR=1 CLAUDE_AGENT_NAME="renamed-agent" load_config
    run jq -r '.agent.id' "${AMP_DIR}/config.json"
    assert_output "11111111-2222-3333-4444-555555555555"
}

@test "load_config: an explicit repair rewrites the address too" {
    AMP_ALLOW_CONFIG_REPAIR=1 CLAUDE_AGENT_NAME="renamed-agent" load_config
    run jq -r '.agent.address' "${AMP_DIR}/config.json"
    assert_output "renamed-agent@testorg.aimaestro.local"
}

# --- --id means "this other agent", so the caller's name is irrelevant --------

@test "load_config: AMP_EXPLICIT_ID suppresses the name comparison entirely" {
    # The caller named a specific agent. CLAUDE_AGENT_NAME is the CALLER's and
    # says nothing about the target, so there is nothing to compare.
    run env CLAUDE_AGENT_NAME="the-caller" AMP_EXPLICIT_ID="11111111-2222-3333-4444-555555555555" \
        bash -c "source '${SCRIPTS_DIR}/amp-helper.sh'; load_config"
    refute_output --partial "mismatch"
}

@test "load_config: AMP_EXPLICIT_ID does not repair even when told it may" {
    local before after
    before=$(cat "${AMP_DIR}/config.json")
    AMP_ALLOW_CONFIG_REPAIR=1 CLAUDE_AGENT_NAME="the-caller" \
        AMP_EXPLICIT_ID="11111111-2222-3333-4444-555555555555" load_config
    after=$(cat "${AMP_DIR}/config.json")
    [ "$before" = "$after" ]
}

# --- --id beats an inherited AMP_DIR -----------------------------------------

@test "--id overrides an inherited AMP_DIR" {
    # AI Maestro exports AMP_DIR into every agent session. Before the fix the
    # helper skipped resolution whenever AMP_DIR was set, so --id was ignored
    # and the caller read its own mailbox.
    local target_uuid="99999999-8888-7777-6666-555555555555"
    local target_dir="${HOME}/.agent-messaging/agents/${target_uuid}"
    mkdir -p "${target_dir}/keys" "${target_dir}/messages/inbox" "${target_dir}/messages/sent"
    cat > "${target_dir}/config.json" <<EOF
{"version":"1.1","agent":{"name":"target-agent","tenant":"testorg","address":"target-agent@testorg.aimaestro.local","fingerprint":"SHA256:x","id":"${target_uuid}"},"provider":{"domain":"aimaestro.local","maestro_url":"${AMP_MAESTRO_URL}"}}
EOF
    cp "${AMP_DIR}/keys/private.pem" "${target_dir}/keys/private.pem"
    cp "${AMP_DIR}/keys/public.pem" "${target_dir}/keys/public.pem"

    # AMP_DIR points at the CALLER; --id names the TARGET.
    run env AMP_DIR="${AMP_DIR}" CLAUDE_AGENT_NAME="testagent" \
        bash "${SCRIPTS_DIR}/amp-status.sh" --id "${target_uuid}"
    assert_output --partial "target-agent"
    refute_output --partial "testagent"
}

@test "reading another agent with --id leaves its config byte-identical" {
    local target_uuid="99999999-8888-7777-6666-555555555555"
    local target_dir="${HOME}/.agent-messaging/agents/${target_uuid}"
    mkdir -p "${target_dir}/keys" "${target_dir}/messages/inbox" "${target_dir}/messages/sent"
    cat > "${target_dir}/config.json" <<EOF
{"version":"1.1","agent":{"name":"target-agent","tenant":"testorg","address":"target-agent@testorg.aimaestro.local","fingerprint":"SHA256:x","id":"${target_uuid}"},"provider":{"domain":"aimaestro.local","maestro_url":"${AMP_MAESTRO_URL}"}}
EOF
    cp "${AMP_DIR}/keys/private.pem" "${target_dir}/keys/private.pem"
    cp "${AMP_DIR}/keys/public.pem" "${target_dir}/keys/public.pem"
    local before after
    before=$(cat "${target_dir}/config.json")

    # The field reproduction: --id takes effect (no AMP_DIR to override it) and
    # the caller's CLAUDE_AGENT_NAME is what the old auto-fix wrote into the
    # target's config.
    env -u AMP_DIR CLAUDE_AGENT_NAME="testagent" \
        bash "${SCRIPTS_DIR}/amp-inbox.sh" --id "${target_uuid}" >/dev/null 2>&1 || true

    after=$(cat "${target_dir}/config.json")
    [ "$before" = "$after" ]
}
