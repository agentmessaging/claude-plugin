#!/usr/bin/env bats
# Row 2 of the status line carries the facts the dashboard chat header shows
# (model, context, cost, effort, prompt cache, time since the last turn), and the
# script reports the same facts to AI Maestro. --install keeps the line ticking
# while the session is idle.

setup() {
    load '../test_helper'
    setup_amp_env
    UUID="11111111-2222-3333-4444-555555555555"
    mkdir -p "${HOME}/.agent-messaging/agents/${UUID}/messages/inbox"
    cat > "${HOME}/.agent-messaging/agents/${UUID}/config.json" <<JSON
{"agent":{"name":"web-agent","address":"web-agent@acme.aimaestro.local"}}
JSON
    export AMP_AGENT_ID="$UUID"
    DIR="${HOME}/work/acme"
    mkdir -p "$DIR"

    # A curl that records instead of connecting: the URL and the -d body.
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$STUB_BIN"
    cat > "${STUB_BIN}/curl" <<'STUB'
#!/bin/bash
url=""; body=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d) body="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "$url" in
    */status-snapshot) echo "$url" >> "${CURL_LOG_DIR}/snapshot.urls"; echo "$body" >> "${CURL_LOG_DIR}/snapshot.bodies" ;;
    *) echo "$url" >> "${CURL_LOG_DIR}/other.urls" ;;
esac
STUB
    chmod +x "${STUB_BIN}/curl"
    export CURL_LOG_DIR="${BATS_TEST_TMPDIR}/curl"
    mkdir -p "$CURL_LOG_DIR"
    export PATH="${STUB_BIN}:${PATH}"
}

# Run the script the way Claude Code does: JSON on stdin, COLUMNS in the env.
# Args: a jq filter-free JSON object merged over the defaults.
run_status() {
    local extra="${1:-{\}}"
    jq -n -c --argjson extra "$extra" --arg dir "$DIR" '
        {model:{display_name:"Opus 5.5", id:"claude-opus-5-5"},
         context_window:{used_percentage:16, total_input_tokens:160000, context_window_size:1000000},
         cost:{total_cost_usd:65.78}, session_id:"sess-1",
         workspace:{current_dir:$dir}} * $extra' \
        | COLUMNS=300 bash "${SCRIPTS_DIR}/amp-statusline.sh"
}

# A transcript file last written N seconds ago.
transcript_aged() {
    local secs="$1" f="${BATS_TEST_TMPDIR}/transcript.jsonl"
    echo '{}' > "$f"
    python3 -c "import os,sys,time; t=time.time()-float(sys.argv[2]); os.utime(sys.argv[1],(t,t))" "$f" "$secs"
    echo "$f"
}

wait_for_post() {
    local i
    for i in $(seq 1 30); do
        [ -s "${CURL_LOG_DIR}/snapshot.bodies" ] && return 0
        sleep 0.1
    done
    return 1
}

@test "row 2: model, ctx, cost, effort, warm cache and idle time in one line" {
    now=$(date +%s)
    t=$(transcript_aged 420)
    run run_status "{\"effort\":{\"level\":\"high\"},\"prompt_cache\":{\"warm\":true,\"expires_at\":$((now + 720))},\"transcript_path\":\"$t\"}"
    assert_success
    assert_line --index 1 "Opus 5.5 | ctx $(printf '\033[33m')160k (16%) · /compact soon$(printf '\033[0m') | \$65.78 | effort high | cache warm 12m | last turn 7m ago"
}

@test "row 2: a cold cache says cache cold" {
    run run_status '{"prompt_cache":{"warm":false}}'
    assert_line --index 1 --partial "| cache cold"
}

@test "row 2: warm but already past its expiry reads as cold" {
    run run_status "{\"prompt_cache\":{\"warm\":true,\"expires_at\":$(( $(date +%s) - 30 ))}}"
    assert_line --index 1 --partial "| cache cold"
    refute_line --index 1 --partial "cache warm"
}

@test "row 2: no prompt_cache block means no cache part" {
    run run_status '{}'
    refute_line --index 1 --partial "cache"
}

@test "row 2: no effort block means no effort part" {
    run run_status '{}'
    refute_line --index 1 --partial "effort"
}

@test "row 2: last turn is hidden within 2 minutes and shown after" {
    t=$(transcript_aged 90)
    run run_status "{\"transcript_path\":\"$t\"}"
    refute_line --index 1 --partial "last turn"
    t=$(transcript_aged 150)
    run run_status "{\"transcript_path\":\"$t\"}"
    assert_line --index 1 --partial "| last turn 2m ago"
}

@test "row 2: a missing transcript is silently skipped" {
    run run_status "{\"transcript_path\":\"${BATS_TEST_TMPDIR}/nope.jsonl\"}"
    assert_success
    refute_line --index 1 --partial "last turn"
}

@test "row 2: an unknown cost field still prints a cost, unknown parts are omitted" {
    run bash -c 'printf "{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"%s\"}}" "$1" | COLUMNS=300 bash "$2/amp-statusline.sh"' _ "$DIR" "$SCRIPTS_DIR"
    assert_line --index 1 --partial "Opus | ctx"
    refute_line --index 1 --partial "effort"
    refute_line --index 1 --partial "cache"
}

@test "report: one POST with the session's facts" {
    now=$(date +%s)
    run run_status "{\"effort\":{\"level\":\"high\"},\"prompt_cache\":{\"warm\":true,\"expires_at\":$((now + 720))}}"
    assert_success
    wait_for_post
    run cat "${CURL_LOG_DIR}/snapshot.urls"
    assert_output "http://localhost:99999/api/agents/${UUID}/status-snapshot"
    body=$(head -1 "${CURL_LOG_DIR}/snapshot.bodies")
    [ "$(echo "$body" | jq -r .sessionId)" = "sess-1" ]
    [ "$(echo "$body" | jq -r .model)" = "Opus 5.5" ]
    [ "$(echo "$body" | jq -r .modelId)" = "claude-opus-5-5" ]
    [ "$(echo "$body" | jq -r .contextTokens)" = "160000" ]
    [ "$(echo "$body" | jq -r .contextWindow)" = "1000000" ]
    [ "$(echo "$body" | jq -r .contextPercent)" = "16" ]
    [ "$(echo "$body" | jq -r .cost)" = "65.78" ]
    [ "$(echo "$body" | jq -r .effort)" = "high" ]
    [ "$(echo "$body" | jq -r .cacheWarm)" = "true" ]
    [ "$(echo "$body" | jq -r .cacheExpiresAt)" = "$((now + 720))" ]
    [ "$(echo "$body" | jq -r .exceeds200k)" = "false" ]
    [ "$(echo "$body" | jq -r '.ts | type')" = "number" ]
}

@test "report: unknown values are null, not empty strings" {
    run run_status '{}'
    wait_for_post
    body=$(head -1 "${CURL_LOG_DIR}/snapshot.bodies")
    [ "$(echo "$body" | jq -r '.effort')" = "null" ]
    [ "$(echo "$body" | jq -r '.cacheWarm')" = "null" ]
    [ "$(echo "$body" | jq -r '.cacheExpiresAt')" = "null" ]
}

@test "report: a second render within 10 s with the same values does not post again" {
    run run_status '{}'
    wait_for_post
    run run_status '{}'
    sleep 0.5
    [ "$(wc -l < "${CURL_LOG_DIR}/snapshot.bodies" | tr -d ' ')" = "1" ]
}

@test "report: a changed cost posts again at once" {
    run run_status '{}'
    wait_for_post
    run run_status '{"cost":{"total_cost_usd":66.5}}'
    for i in $(seq 1 30); do
        [ "$(wc -l < "${CURL_LOG_DIR}/snapshot.bodies" | tr -d ' ')" = "2" ] && break
        sleep 0.1
    done
    [ "$(wc -l < "${CURL_LOG_DIR}/snapshot.bodies" | tr -d ' ')" = "2" ]
    [ "$(tail -1 "${CURL_LOG_DIR}/snapshot.bodies" | jq -r .cost)" = "66.5" ]
}

@test "report: a changed effort posts again at once" {
    run run_status '{"effort":{"level":"medium"}}'
    wait_for_post
    run run_status '{"effort":{"level":"high"}}'
    for i in $(seq 1 30); do
        [ "$(wc -l < "${CURL_LOG_DIR}/snapshot.bodies" | tr -d ' ')" = "2" ] && break
        sleep 0.1
    done
    [ "$(tail -1 "${CURL_LOG_DIR}/snapshot.bodies" | jq -r .effort)" = "high" ]
}

@test "report: nothing is sent when no agent resolves" {
    export AMP_AGENT_ID="99999999-0000-0000-0000-000000000000"
    run run_status '{}'
    assert_success
    sleep 0.5
    [ ! -s "${CURL_LOG_DIR}/snapshot.bodies" ]
}

@test "report: the render never prints anything from the report" {
    run run_status '{}'
    assert_success
    [ "${#lines[@]}" = "2" ]
}

# ---- --install keeps the line ticking while idle ----

settings() { echo "${HOME}/.claude/settings.json"; }

@test "install: a fresh install sets refreshInterval 60" {
    mkdir -p "${HOME}/.claude"
    run bash "${SCRIPTS_DIR}/amp-statusline.sh" --install
    assert_success
    [ "$(jq -r .statusLine.refreshInterval "$(settings)")" = "60" ]
    [ "$(jq -r .statusLine.type "$(settings)")" = "command" ]
}

@test "install: an existing install of this script is updated without a prompt" {
    mkdir -p "${HOME}/.claude"
    echo '{"statusLine":{"type":"command","command":"/old/place/amp-statusline.sh","padding":2},"other":true}' > "$(settings)"
    run bash "${SCRIPTS_DIR}/amp-statusline.sh" --install < /dev/null
    assert_success
    assert_output --partial "updated"
    [ "$(jq -r .statusLine.refreshInterval "$(settings)")" = "60" ]
    [ "$(jq -r .statusLine.padding "$(settings)")" = "2" ]
    [ "$(jq -r .other "$(settings)")" = "true" ]
    [ "$(jq -r .statusLine.command "$(settings)")" = "${SCRIPTS_DIR}/amp-statusline.sh" ]
}

@test "install: a refreshInterval the user already set is kept" {
    mkdir -p "${HOME}/.claude"
    echo '{"statusLine":{"type":"command","command":"/x/amp-statusline.sh","refreshInterval":15}}' > "$(settings)"
    run bash "${SCRIPTS_DIR}/amp-statusline.sh" --install < /dev/null
    [ "$(jq -r .statusLine.refreshInterval "$(settings)")" = "15" ]
}

@test "install: someone else's status line is not replaced without a yes" {
    mkdir -p "${HOME}/.claude"
    echo '{"statusLine":{"type":"command","command":"/usr/local/bin/other-line.sh"}}' > "$(settings)"
    run bash "${SCRIPTS_DIR}/amp-statusline.sh" --install < /dev/null
    assert_success
    [ "$(jq -r .statusLine.command "$(settings)")" = "/usr/local/bin/other-line.sh" ]
    [ "$(jq -r '.statusLine.refreshInterval // "none"' "$(settings)")" = "none" ]
}

@test "row 2: a long idle uses hours and days, like the dashboard header" {
    t=$(transcript_aged $(( 125 * 60 )))
    run run_status "{\"transcript_path\":\"$t\"}"
    assert_line --index 1 --partial "| last turn 2h ago"
    t=$(transcript_aged $(( 3 * 24 * 3600 + 600 )))
    run run_status "{\"transcript_path\":\"$t\"}"
    assert_line --index 1 --partial "| last turn 3d ago"
}
