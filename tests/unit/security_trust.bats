#!/usr/bin/env bats
# =============================================================================
# Tests: determine_trust_level() - verified, external, untrusted
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    source_amp_helper
}

@test "trust: same tenant + valid sig = verified" {
    local trust
    trust=$(determine_trust_level "alice@testorg.aimaestro.local" "true" "testorg")
    assert_equal "$trust" "verified"
}

@test "trust: different tenant + valid sig = external" {
    local trust
    trust=$(determine_trust_level "bob@otherorb.aimaestro.local" "true" "testorg")
    assert_equal "$trust" "external"
}

@test "trust: invalid signature = untrusted" {
    local trust
    trust=$(determine_trust_level "alice@testorg.aimaestro.local" "false" "testorg")
    assert_equal "$trust" "untrusted"
}

@test "trust: missing signature = untrusted" {
    local trust
    trust=$(determine_trust_level "alice@testorg.aimaestro.local" "" "testorg")
    assert_equal "$trust" "untrusted"
}

@test "trust: external provider + valid sig = external" {
    local trust
    trust=$(determine_trust_level "carol@acme.crabmail.ai" "true" "testorg")
    assert_equal "$trust" "external"
}

@test "trust: external provider + invalid sig = untrusted" {
    local trust
    trust=$(determine_trust_level "carol@acme.crabmail.ai" "false" "testorg")
    assert_equal "$trust" "untrusted"
}
