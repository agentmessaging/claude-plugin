#!/usr/bin/env bats
# =============================================================================
# Tests: the first hour on a clean machine
# =============================================================================
#
# Found by running the install as a reader would, on a bare Ubuntu container:
#
#   1. The fallback UUID (no uuidgen) had a five-character group. It is not a UUID, so every check that
#      tests for one took the agent's folder for a NAME and printed "AMP config mismatch" on every command.
#   2. `amp-init --name bob` after `amp-init --name alice` said "already initialized" as alice and never
#      created bob (exactly one identity on the machine is picked for any folder).
#   3. An agent created in AI Maestro first (dashboard or aimaestro-agent.sh create) got a SECOND id from
#      amp-init, so mail landed in an inbox the server never watched and the agent was never woken.
#   4. xxd is not on a clean machine; three places needed it.

setup() {
    load '../test_helper'
    setup_amp_env
    unset AMP_DIR
    AGENTS="${HOME}/.agent-messaging/agents"
    mkdir -p "${HOME}/agents/alice" "${HOME}/agents/bob"
}

@test "the fallback UUID is a real UUID" {
    local bin="${BATS_TEST_TMPDIR}/nouuidgen"
    mkdir -p "$bin"
    for t in od head awk tr bash; do ln -s "$(command -v $t)" "${bin}/$t"; done
    run env PATH="$bin" "${bin}/bash" -c "
        $(sed -n '/^generate_uuid()/,/^}/p' "${SCRIPTS_DIR}/amp-helper.sh")
        for i in 1 2 3 4 5 6 7 8; do generate_uuid; done"
    assert_success
    while IFS= read -r u; do
        [[ "$u" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || { echo "not a UUID: $u"; return 1; }
    done <<< "$output"
}

@test "no script needs xxd" {
    run /usr/bin/grep -n "xxd" "${SCRIPTS_DIR}"/*.sh
    assert_failure
}

@test "a second agent is created, not reported as the first one" {
    mock_curl "000" ""
    cd "${HOME}/agents/alice"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name alice --tenant acme
    assert_success
    local alice_dir
    alice_dir=$(jq -r '.alice' "${AGENTS}/.index.json")
    local alice_key_before
    alice_key_before=$(cksum < "${AGENTS}/${alice_dir}/keys/private.pem")

    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name bob --tenant acme
    assert_success
    refute_output --partial "already initialized"
    run jq -r 'keys | join(",")' "${AGENTS}/.index.json"
    assert_output "alice,bob"
    # alice is untouched
    run jq -r '.agent.name' "${AGENTS}/${alice_dir}/config.json"
    assert_output "alice"
    run bash -c "cksum < '${AGENTS}/${alice_dir}/keys/private.pem'"
    assert_output "$alice_key_before"
}

@test "--force for a second agent never re-keys the first one" {
    mock_curl "000" ""
    cd "${HOME}/agents/alice"
    bash "${SCRIPTS_DIR}/amp-init.sh" --name alice --tenant acme >/dev/null
    local alice_dir alice_id
    alice_dir=$(jq -r '.alice' "${AGENTS}/.index.json")
    alice_id=$(jq -r '.agent.id' "${AGENTS}/${alice_dir}/config.json")
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name bob --tenant acme --force
    assert_success
    run jq -r '.agent.name + " " + .agent.id' "${AGENTS}/${alice_dir}/config.json"
    assert_output "alice ${alice_id}"
    run jq -r '.bob' "${AGENTS}/.index.json"
    refute_output "$alice_dir"
}

@test "an agent AI Maestro already has keeps its id when amp-init runs" {
    local id="66a02f9a-ca43-405b-bdb4-84d6b0eb2de8"
    mock_curl "201" "{\"agents\":[{\"name\":\"bob\",\"id\":\"${id}\"}],\"api_key\":\"amp_live_sk_test\",\"address\":\"bob@acme.aimaestro.local\",\"agent_id\":\"${id}\",\"provider\":{\"name\":\"aimaestro.local\",\"endpoint\":\"http://localhost:99999/api/v1\"}}"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name bob --tenant acme
    assert_success
    assert_output --partial "Using the id AI Maestro already has"
    run jq -r '.bob' "${AGENTS}/.index.json"
    assert_output "$id"
    run jq -r '.agent.id' "${AGENTS}/${id}/config.json"
    assert_output "$id"
    [ "$(ls "${AGENTS}" | /usr/bin/grep -c -E '^[0-9a-f]{8}-')" = "1" ]
}

@test "two agents with the same name in AI Maestro are not guessed between" {
    mock_curl "000" '{"agents":[{"name":"bob","id":"66a02f9a-ca43-405b-bdb4-84d6b0eb2de8"},{"name":"bob","id":"11111111-2222-4333-8444-555555555555"}]}'
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name bob --tenant acme
    refute_output --partial "Using the id AI Maestro already has"
}

@test "the organization-not-configured failure says what to do" {
    mock_curl "400" '{"error":"organization_not_configured","message":"Organization must be configured before registering agents. Please complete the AI Maestro setup first."}'
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    cd "${HOME}/agents/bob"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name bob --tenant acme
    assert_output --partial "enter your organization name once"
    assert_output --partial "amp-init --name bob --force"
}

@test "a third agent can be created once two exist" {
    mock_curl "000" ""
    for a in alice bob; do
        mkdir -p "${HOME}/agents/${a}"
        (cd "${HOME}/agents/${a}" && bash "${SCRIPTS_DIR}/amp-init.sh" --name "$a" --tenant acme >/dev/null)
    done
    mkdir -p "${HOME}/agents/carol"
    cd "${HOME}/agents/carol"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name carol --tenant acme --remember
    assert_success
    refute_output --partial "Multiple AMP agents found"
    run jq -r 'keys | join(",")' "${AGENTS}/.index.json"
    assert_output "alice,bob,carol"
    run jq -r '.env.CLAUDE_AGENT_NAME' "${HOME}/agents/carol/.claude/settings.local.json"
    assert_output "carol"
}
