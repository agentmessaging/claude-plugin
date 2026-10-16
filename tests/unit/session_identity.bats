#!/usr/bin/env bats
# =============================================================================
# Tests: a session is never named after an agent it does not belong to
# =============================================================================
#
# Reported by an agent that registered with `amp-init --name sebastian` and then
# found `amp-identity` answering as a DIFFERENT agent. The folder lookup took the
# AI Maestro agent that owned /private/tmp as the owner of every folder below it,
# so any scratch folder became that agent. Registering also left nothing behind
# that said which agent a later session in the same folder was, and the status
# line answered "not configured (run amp-init)" for a session that had simply
# never been named.

setup() {
    load '../test_helper'
    setup_amp_env
    AGENTS="${HOME}/.agent-messaging/agents"
    # Not a scratch folder the test host happens to own
    mkdir -p "${HOME}/work/project/app" "${HOME}/scratch"
}

# Two registered agents on this machine, and a session that names neither.
seed_agents() {
    A1="aaaaaaaa-0000-0000-0000-000000000001"
    A2="aaaaaaaa-0000-0000-0000-000000000002"
    for pair in "alpha:${A1}" "beta:${A2}"; do
        n="${pair%%:*}"; u="${pair##*:}"
        mkdir -p "${AGENTS}/${u}/messages/inbox" "${AGENTS}/${u}/keys"
        cat > "${AGENTS}/${u}/config.json" <<JSON
{"version":"1.1","agent":{"name":"${n}","tenant":"acme","address":"${n}@acme.aimaestro.local","id":"${u}","fingerprint":"SHA256:x"}}
JSON
        AMP_DIR="${AGENTS}/${u}" create_test_keys
    done
    printf '{"alpha":"%s","beta":"%s"}' "$A1" "$A2" > "${AGENTS}/.index.json"
    unset AMP_DIR
}

# AI Maestro's agent list, as the folder lookup sees it.
maestro_agents() {
    seed_agents
    mock_curl "200" "$1"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

who() {
    cd "$1" && bash "${SCRIPTS_DIR}/amp-identity.sh" 2>&1
}

@test "a folder under a broad owner (HOME) is NOT taken for that agent" {
    maestro_agents "{\"agents\":[{\"name\":\"alpha\",\"workingDirectory\":\"${HOME}\"}]}"
    run who "${HOME}/scratch"
    assert_failure
    assert_output --partial "Multiple AMP agents found"
    refute_output --partial "AMP Identity Verified"
}

@test "a broad owner still matches the exact folder it owns" {
    maestro_agents "{\"agents\":[{\"name\":\"alpha\",\"workingDirectory\":\"${HOME}\"}]}"
    run who "${HOME}"
    assert_success
    assert_output --partial "alpha@acme.aimaestro.local"
}

@test "a project folder owned by one agent still names sessions below it" {
    maestro_agents "{\"agents\":[{\"name\":\"alpha\",\"workingDirectory\":\"${HOME}\"},{\"name\":\"beta\",\"workingDirectory\":\"${HOME}/work/project\"}]}"
    run who "${HOME}/work/project/app"
    assert_success
    assert_output --partial "beta@acme.aimaestro.local"
}

@test "the error for an unnamed session says how to name it once" {
    maestro_agents '{"agents":[]}'
    run who "${HOME}/scratch"
    assert_failure
    assert_output --partial "amp-init --name <your-agent> --remember"
}

# ---- the status line -------------------------------------------------------

status_line() {
    printf '{"workspace":{"current_dir":"%s"}}' "$1" | COLUMNS=200 bash "${SCRIPTS_DIR}/amp-statusline.sh"
}

@test "status line: a session with no agent name says so, not 'not configured'" {
    maestro_agents '{"agents":[]}'
    run status_line "${HOME}/scratch"
    assert_success
    assert_line --index 0 --partial "this session has no agent name"
    assert_line --index 0 --partial "--remember"
    refute_output --partial "not configured"
}

@test "status line: a named agent with no address still says not configured" {
    export AMP_AGENT_ID="99999999-0000-0000-0000-000000000000"
    run status_line "${HOME}/scratch"
    assert_line --index 0 "AMP: not configured (run amp-init)"
}

@test "status line: a broad owner does not name a scratch folder" {
    maestro_agents "{\"agents\":[{\"name\":\"alpha\",\"workingDirectory\":\"${HOME}\"}]}"
    run status_line "${HOME}/scratch"
    refute_output --partial "alpha@"
    assert_line --index 0 --partial "no agent name"
}

# ---- amp-init --remember and the registration --------------------------------

@test "amp-init --remember writes the name hint into this folder and keeps other settings" {
    mock_curl "000" ""
    mkdir -p "${HOME}/work/project/.claude"
    echo '{"permissions":{"allow":["Bash(ls:*)"]},"env":{"FOO":"1"}}' > "${HOME}/work/project/.claude/settings.local.json"
    cd "${HOME}/work/project"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name gamma --tenant acme --remember
    assert_success
    run jq -r '.env.CLAUDE_AGENT_NAME, .env.FOO, .permissions.allow[0]' "${HOME}/work/project/.claude/settings.local.json"
    assert_line --index 0 "gamma"
    assert_line --index 1 "1"
    assert_line --index 2 "Bash(ls:*)"
}

@test "amp-init --remember refuses a broad folder" {
    mock_curl "000" ""
    cd "${HOME}"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name gamma --tenant acme --remember
    assert_output --partial "too broad"
    [ ! -f "${HOME}/.claude/settings.local.json" ]
}

@test "amp-init --remember leaves a settings file that is not JSON alone" {
    mock_curl "000" ""
    mkdir -p "${HOME}/work/project/.claude"
    echo 'not json' > "${HOME}/work/project/.claude/settings.local.json"
    cd "${HOME}/work/project"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name gamma --tenant acme --remember
    assert_output --partial "is not a JSON object"
    run cat "${HOME}/work/project/.claude/settings.local.json"
    assert_output "not json"
}

@test "amp-init without --remember points at the one command that makes it stick" {
    mock_curl "000" ""
    cd "${HOME}/work/project"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name gamma --tenant acme
    assert_success
    assert_output --partial "amp-init --name gamma --remember"
    [ ! -f "${HOME}/work/project/.claude/settings.local.json" ]
}

@test "registration tells the provider the project folder, but never a broad one" {
    mock_curl "201" '{"api_key":"amp_live_sk_test","address":"gamma@acme.aimaestro.local","agent_id":"x","provider":{"name":"aimaestro.local","endpoint":"http://localhost:99999/api/v1"}}'
    cd "${HOME}/work/project"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name gamma --tenant acme
    assert_success
    run /usr/bin/grep -c "working_directory" "${BATS_TEST_TMPDIR}/curl_calls.log"
    assert_output "1"
    rm -rf "${HOME}/.agent-messaging/agents/"*gamma* ; : > "${BATS_TEST_TMPDIR}/curl_calls.log"
    rm -rf "${AGENTS}"; mkdir -p "${AGENTS}"
    cd "${HOME}"
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name delta --tenant acme
    run /usr/bin/grep -c "working_directory" "${BATS_TEST_TMPDIR}/curl_calls.log"
    assert_output "0"
}
