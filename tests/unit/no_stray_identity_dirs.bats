#!/usr/bin/env bats
# =============================================================================
# Tests: a wrong inference must not manufacture an identity
# =============================================================================
#
# Root cause of the second half of the salesland-dev-3metas report ("first run
# exited 0 having persisted nothing").
#
# amp-helper resolves AMP_DIR from the working directory when nothing more
# explicit is available: a .claude/settings.local.json hint, else the AI Maestro
# agent that uniquely owns $PWD. That is an INFERENCE about which agent a
# directory belongs to. It was being treated as licence to CREATE that agent's
# identity — so a hint naming an agent with no entry in this home fell through
# to the raw name path and the auto-create manufactured an empty shell:
# keys/, messages/, registrations/, no config.
#
# Reproduced from a clean home: one `amp-init --name foo` run inside a project
# whose settings.local.json names a different agent produced TWO directories —
# the real uuid one and a stray shell for the unrelated name — because amp-init
# overrides AMP_DIR only after the helper has already created the wrong one.
#
# The shells are not harmless. A later name-based resolution can select the
# empty shell over the real identity, which is one of the ways an agent ends up
# looking unregistered or reading an empty inbox.

setup() {
    load '../test_helper'
    setup_amp_env
    export AMP_AGENTS_BASE="${HOME}/.agent-messaging/agents"
    mkdir -p "$AMP_AGENTS_BASE"
}

@test "a cwd hint for an unknown agent does not create a directory for it" {
    # No index entry, no existing directory: the inference was wrong.
    local project="${BATS_TEST_TMPDIR}/project"
    mkdir -p "${project}/.claude"
    echo '{"env":{"CLAUDE_AGENT_NAME":"some-other-agent"}}' > "${project}/.claude/settings.local.json"

    run env -u AMP_DIR -u CLAUDE_AGENT_NAME -u CLAUDE_AGENT_ID -u TMUX \
        HOME="$HOME" AMP_AGENTS_BASE="$AMP_AGENTS_BASE" \
        bash -c "cd '${project}' && source '${SCRIPTS_DIR}/amp-helper.sh'" 2>/dev/null

    [ ! -d "${AMP_AGENTS_BASE}/some-other-agent" ]
}

@test "a cwd hint for a KNOWN agent still resolves" {
    # The inference is good when the identity actually exists here.
    local uuid="11111111-2222-3333-4444-555555555555"
    mkdir -p "${AMP_AGENTS_BASE}/${uuid}/keys" "${AMP_AGENTS_BASE}/${uuid}/messages/inbox"
    echo "{\"known-agent\":\"${uuid}\"}" > "${AMP_AGENTS_BASE}/.index.json"

    local project="${BATS_TEST_TMPDIR}/project2"
    mkdir -p "${project}/.claude"
    echo '{"env":{"CLAUDE_AGENT_NAME":"known-agent"}}' > "${project}/.claude/settings.local.json"

    run env -u AMP_DIR -u CLAUDE_AGENT_NAME -u CLAUDE_AGENT_ID -u TMUX \
        HOME="$HOME" AMP_AGENTS_BASE="$AMP_AGENTS_BASE" \
        bash -c "cd '${project}' && source '${SCRIPTS_DIR}/amp-helper.sh' && echo \$AMP_DIR"
    assert_output --partial "$uuid"
}

@test "an unresolved identity fails loudly for ordinary scripts" {
    # Everything except amp-init must keep refusing to guess.
    run env -u AMP_DIR -u CLAUDE_AGENT_NAME -u CLAUDE_AGENT_ID -u TMUX -u AMP_ALLOW_UNRESOLVED \
        HOME="$HOME" AMP_AGENTS_BASE="$AMP_AGENTS_BASE" \
        bash -c "cd '${BATS_TEST_TMPDIR}' && source '${SCRIPTS_DIR}/amp-helper.sh'"
    assert_failure
    assert_output --partial "AMP not initialized"
}

@test "amp-init is exempt, because creating an identity is its job" {
    # Before the exemption, init only worked when SOMETHING resolved — so it
    # depended on a cwd inference firing, and on a clean home with no project
    # hint it failed outright. The dependency was invisible because the
    # inference almost always fired.
    run env -u AMP_DIR -u CLAUDE_AGENT_NAME -u CLAUDE_AGENT_ID -u TMUX \
        AMP_ALLOW_UNRESOLVED=1 HOME="$HOME" AMP_AGENTS_BASE="$AMP_AGENTS_BASE" \
        bash -c "cd '${BATS_TEST_TMPDIR}' && source '${SCRIPTS_DIR}/amp-helper.sh' && echo ok"
    assert_success
}

@test "the unresolved placeholder is never created on disk" {
    env -u AMP_DIR -u CLAUDE_AGENT_NAME -u CLAUDE_AGENT_ID -u TMUX \
        AMP_ALLOW_UNRESOLVED=1 HOME="$HOME" AMP_AGENTS_BASE="$AMP_AGENTS_BASE" \
        bash -c "cd '${BATS_TEST_TMPDIR}' && source '${SCRIPTS_DIR}/amp-helper.sh'" >/dev/null 2>&1 || true
    [ ! -d "${AMP_AGENTS_BASE}/.uninitialized" ]
}
