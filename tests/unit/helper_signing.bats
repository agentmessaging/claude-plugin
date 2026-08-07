#!/usr/bin/env bats
# =============================================================================
# Tests: sign_message() and verify_signature() - Ed25519 round-trip
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "signer" "testorg"
    create_test_keys
    source_amp_helper
}

@test "sign_message: produces base64 signature" {
    local sig
    sig=$(sign_message "test|data|to|sign|reply|hash")
    # Ed25519 signatures are 64 bytes → 88 chars base64
    [ -n "$sig" ]
    # Should be valid base64 (no errors when decoding)
    echo "$sig" | base64 -d > /dev/null 2>&1
}

@test "sign_message: signatures are deterministic for same input" {
    local sig1 sig2
    sig1=$(sign_message "identical-data")
    sig2=$(sign_message "identical-data")
    # Ed25519 is deterministic (RFC 8032)
    assert_equal "$sig1" "$sig2"
}

@test "sign_message: different inputs produce different signatures" {
    local sig1 sig2
    sig1=$(sign_message "data-one")
    sig2=$(sign_message "data-two")
    [ "$sig1" != "$sig2" ]
}

@test "verify_signature: verifies valid signature" {
    local data="from@test.local|to@test.local|Subject|normal||payloadhash"
    local sig
    sig=$(sign_message "$data")
    run verify_signature "$data" "$sig" "${AMP_DIR}/keys/public.pem"
    assert_success
}

@test "verify_signature: rejects wrong data" {
    local data="original-data"
    local sig
    sig=$(sign_message "$data")
    run verify_signature "tampered-data" "$sig" "${AMP_DIR}/keys/public.pem"
    assert_failure
}

@test "verify_signature: rejects wrong key" {
    local data="test-data"
    local sig
    sig=$(sign_message "$data")

    # Generate a different keypair
    local other_dir="${BATS_TEST_TMPDIR}/other_keys"
    mkdir -p "$other_dir"
    local openssl_bin
    openssl_bin=$(_find_openssl)
    $openssl_bin genpkey -algorithm Ed25519 -out "${other_dir}/private.pem" 2>/dev/null
    $openssl_bin pkey -in "${other_dir}/private.pem" -pubout -out "${other_dir}/public.pem" 2>/dev/null

    run verify_signature "$data" "$sig" "${other_dir}/public.pem"
    assert_failure
}

@test "sign_message: fails without private key" {
    rm -f "${AMP_DIR}/keys/private.pem"
    run sign_message "test-data"
    assert_failure
    assert_output --partial "No private key"
}

@test "verify_signature: canonical format round-trip" {
    # Test with the exact canonical format used by AMP
    local from="sender@testorg.aimaestro.local"
    local to="alice@testorg.aimaestro.local"
    local subject="Test Message"
    local priority="normal"
    local reply_to=""
    local payload_hash="dGVzdGhhc2g="

    local canonical="${from}|${to}|${subject}|${priority}|${reply_to}|${payload_hash}"
    local sig
    sig=$(sign_message "$canonical")
    run verify_signature "$canonical" "$sig" "${AMP_DIR}/keys/public.pem"
    assert_success
}
