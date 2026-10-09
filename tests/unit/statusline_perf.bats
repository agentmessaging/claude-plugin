#!/usr/bin/env bats
# The status line counts unread messages in one pass and caches the AI Maestro
# agent lookup; neither may change what it prints.

setup() {
    load '../test_helper'
    setup_amp_env
    UUID="11111111-2222-3333-4444-555555555555"
    INBOX="${HOME}/.agent-messaging/agents/${UUID}/messages/inbox"
    mkdir -p "$INBOX/sender one"
    echo '{"agent":{"name":"web-agent","address":"web-agent@acme.aimaestro.local"}}' \
        > "${HOME}/.agent-messaging/agents/${UUID}/config.json"
    export AMP_AGENT_ID="$UUID"
    for i in 1 2 3; do echo '{"local":{"status":"unread"}}' > "$INBOX/sender one/u$i.json"; done
    echo '{"local":{"status":"read"}}' > "$INBOX/r1.json"
    echo '{"metadata":{"status":"read"}}' > "$INBOX/sender one/r2.json"
    DIR="${HOME}/work"; mkdir -p "$DIR"
}

line() {
    printf '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"}}' "$DIR" \
        | COLUMNS=200 bash "${SCRIPTS_DIR}/amp-statusline.sh"
}

@test "3 unread and 2 read counts 3" {
    run line
    assert_success
    assert_line --index 0 --partial "web-agent · web-agent@acme.aimaestro.local · ~/work | "
    assert_line --index 0 --partial "3 unread"
}

@test "an invalid JSON file does not break the count" {
    echo 'not json' > "$INBOX/bad.json"
    run line
    assert_line --index 0 --partial "3 unread"
}

@test "an empty inbox shows 0 unread" {
    rm -rf "$INBOX"; mkdir -p "$INBOX"
    run line
    assert_line --index 0 --partial "0 unread"
}

@test "the agents lookup is cached for a minute" {
    unset AMP_AGENT_ID
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"; mkdir -p "$TMPDIR"
    stub="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$stub"
    count="${BATS_TEST_TMPDIR}/curl-count"
    cat > "$stub/curl" <<SH
#!/bin/bash
case "\$*" in *"/api/agents") echo x >> "$count";; esac
echo '{"agents":[{"name":"web-agent","workingDirectory":"$DIR"}]}'
SH
    chmod +x "$stub/curl"
    echo "{\"web-agent\":\"$UUID\"}" > "${HOME}/.agent-messaging/agents/.index.json"
    PATH="$stub:$PATH" run line
    assert_line --index 0 --partial "web-agent"
    assert_line --index 0 --partial "3 unread"
    PATH="$stub:$PATH" run line
    assert_line --index 0 --partial "3 unread"
    [ "$(wc -l < "$count" | tr -d ' ')" = "1" ]
}

@test "output is identical to the previous per-file implementation" {
    new=$(line)
    old=$(printf '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"}}' "$DIR" \
        | COLUMNS=200 bash <(git -C "$PLUGIN_DIR" show HEAD:scripts/amp-statusline.sh))
    [ "$new" = "$old" ]
}
