#!/usr/bin/env bats
# =============================================================================
# Tests: hardening from the 2026-10 security review
#   - message ids from other agents never become paths
#   - replay check matches whole ids
#   - private keys and API-key files are 0600, agent dirs 0700
#   - attachment URLs from messages must be http(s)
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
    source_amp_helper
}

mode_of() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

@test "save_to_inbox: refuses a path-traversal message id" {
    local msg='{"envelope":{"id":"../../../escape","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    run save_to_inbox "$msg" "false"
    assert_failure
    assert_output --partial "unsafe id"
    [ ! -e "${AMP_DIR}/../escape.json" ]
}

@test "save_to_inbox: refuses an id starting with a dash" {
    local msg='{"envelope":{"id":"-rf-abcd","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    run save_to_inbox "$msg" "false"
    assert_failure
}

@test "save_to_sent: refuses a path-traversal message id" {
    local msg='{"envelope":{"id":"a/../../b","from":"testagent@testorg.aimaestro.local","to":"bob@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    run save_to_sent "$msg"
    assert_failure
}

@test "save_to_inbox: accepts a provider-assigned UUID id" {
    local msg='{"envelope":{"id":"123e4567-e89b-12d3-a456-426614174000","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    run save_to_inbox "$msg" "false"
    assert_success
}

@test "save_to_inbox: a shorter id that is a prefix of a seen id is not a replay" {
    local m1='{"envelope":{"id":"msg_1000_abcdef","from":"alice@testorg.aimaestro.local","to":"t@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    local m2='{"envelope":{"id":"msg_1000_abc","from":"alice@testorg.aimaestro.local","to":"t@testorg.aimaestro.local","subject":"x","priority":"normal"},"payload":{"type":"notification","message":"x"}}'
    save_to_inbox "$m1" "false" >/dev/null
    run save_to_inbox "$m2" "false"
    assert_success
}

@test "generate_keypair: private key is 0600 and keys dir is 0700" {
    rm -rf "${AMP_KEYS_DIR}"
    generate_keypair >/dev/null
    [ "$(mode_of "${AMP_KEYS_DIR}/private.pem")" = "600" ]
    [ "$(mode_of "${AMP_KEYS_DIR}")" = "700" ]
}

@test "generate_keypair_to: target dir is 0700 and key is 0600" {
    local d="${BATS_TEST_TMPDIR}/rot"
    generate_keypair_to "$d" >/dev/null
    [ "$(mode_of "$d")" = "700" ]
    [ "$(mode_of "$d/private.pem")" = "600" ]
}

@test "ensure_amp_dirs: agent and registrations dirs are 0700" {
    ensure_amp_dirs
    [ "$(mode_of "${AMP_DIR}")" = "700" ]
    [ "$(mode_of "${AMP_REGISTRATIONS_DIR}")" = "700" ]
}

@test "download_attachment: rejects a url that is not http(s)" {
    local att='{"id":"att_abc123","filename":"a.txt","size":3,"digest":"sha256:00","url":"--output=/tmp/pwned"}'
    run download_attachment "$att" "${BATS_TEST_TMPDIR}/dl" "" ""
    assert_failure
    [ ! -e /tmp/pwned ]
}

@test "compute_expiry_date: non-numeric days fall back to 7" {
    run compute_expiry_date '1;touch /tmp/amp-pwn-test'
    assert_success
    [ ! -e /tmp/amp-pwn-test ]
}
