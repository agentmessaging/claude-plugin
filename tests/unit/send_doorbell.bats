#!/usr/bin/env bats
# =============================================================================
# Tests: amp_ring_doorbell (best-effort wake after a same-host inbox write)
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
    unset SCRIPT_DIR

    STUBS="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "$STUBS"
    cat > "${STUBS}/curl" <<STUB
#!/bin/bash
echo "\$@" >> "${BATS_TEST_TMPDIR}/curl.calls"
[ -n "\$CURL_STUB_SLEEP" ] && sleep "\$CURL_STUB_SLEEP"
exit "\${CURL_STUB_EXIT:-0}"
STUB
    chmod +x "${STUBS}/curl"
    export PATH="${STUBS}:${PATH}"
    export AMP_MAESTRO_URL="http://localhost:23000"
}

wait_for_calls() {
    for _ in $(seq 1 30); do
        [ -s "${BATS_TEST_TMPDIR}/curl.calls" ] && return 0
        sleep 0.1
    done
    return 1
}

@test "rings the doorbell with the recipient and message id" {
    run amp_ring_doorbell "agent-uuid-1" "msg_123_abc"
    assert_success
    assert_output ""
    wait_for_calls
    run cat "${BATS_TEST_TMPDIR}/curl.calls"
    assert_output --partial "http://localhost:23000/api/messages/doorbell"
    assert_output --partial '"recipient":"agent-uuid-1"'
    assert_output --partial '"messageId":"msg_123_abc"'
}

@test "prints nothing and succeeds when the server is unreachable" {
    export CURL_STUB_EXIT=7
    run amp_ring_doorbell "a" "m"
    assert_success
    assert_output ""
}

@test "does not wait for a slow server" {
    export CURL_STUB_SLEEP=5
    start=$SECONDS
    run amp_ring_doorbell "a" "m"
    assert_success
    [ $((SECONDS - start)) -lt 3 ]
}

@test "AMP_DOORBELL=0 opts out" {
    export AMP_DOORBELL=0
    run amp_ring_doorbell "a" "m"
    assert_success
    sleep 0.3
    [ ! -e "${BATS_TEST_TMPDIR}/curl.calls" ]
}

@test "does nothing without a recipient or a message id" {
    run amp_ring_doorbell "" "m"
    assert_success
    run amp_ring_doorbell "a" ""
    assert_success
    sleep 0.3
    [ ! -e "${BATS_TEST_TMPDIR}/curl.calls" ]
}

@test "succeeds with curl missing" {
    # Make `command -v curl` fail without touching PATH (other tools stay available)
    command() { if [ "$1" = "-v" ] && [ "$2" = "curl" ]; then return 1; fi; builtin command "$@"; }
    run amp_ring_doorbell "a" "m"
    unset -f command
    assert_success
    assert_output ""
    sleep 0.3
    [ ! -e "${BATS_TEST_TMPDIR}/curl.calls" ]
}

@test "amp-send rings after both local filesystem writes" {
    run grep -c 'amp_ring_doorbell "${RECIPIENT_UUID:-$ADDR_NAME}" "$MSG_ID"' "${SCRIPTS_DIR}/amp-send.sh"
    assert_output "2"
}
