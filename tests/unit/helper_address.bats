#!/usr/bin/env bats
# =============================================================================
# Tests: parse_address() and build_address()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

# --- parse_address: full addresses ---

@test "parse_address: full local address extracts name, tenant, provider" {
    parse_address "alice@acme.aimaestro.local"
    assert_equal "$ADDR_NAME" "alice"
    assert_equal "$ADDR_TENANT" "acme"
    assert_equal "$ADDR_PROVIDER" "aimaestro.local"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

@test "parse_address: external address (crabmail.ai)" {
    parse_address "bob@mycompany.crabmail.ai"
    assert_equal "$ADDR_NAME" "bob"
    assert_equal "$ADDR_TENANT" "mycompany"
    assert_equal "$ADDR_PROVIDER" "crabmail.ai"
    assert_equal "$ADDR_IS_LOCAL" "false"
}

@test "parse_address: scoped address extracts scope" {
    parse_address "bot@myrepo.github.acme.aimaestro.local"
    assert_equal "$ADDR_NAME" "bot"
    assert_equal "$ADDR_TENANT" "acme"
    assert_equal "$ADDR_PROVIDER" "aimaestro.local"
    assert_equal "$ADDR_SCOPE" "myrepo.github"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

@test "parse_address: case normalization (uppercase → lowercase)" {
    parse_address "Alice@ACME.AIMaestro.LOCAL"
    assert_equal "$ADDR_NAME" "alice"
    assert_equal "$ADDR_TENANT" "acme"
    assert_equal "$ADDR_PROVIDER" "aimaestro.local"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

# --- parse_address: short names ---

@test "parse_address: short name uses configured tenant and local provider" {
    parse_address "alice"
    assert_equal "$ADDR_NAME" "alice"
    assert_equal "$ADDR_TENANT" "testorg"
    assert_equal "$ADDR_PROVIDER" "aimaestro.local"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

@test "parse_address: short name case-normalized" {
    parse_address "ALICE"
    assert_equal "$ADDR_NAME" "alice"
}

# --- parse_address: legacy/edge cases ---

@test "parse_address: two-part domain (tenant.local)" {
    parse_address "agent@myteam.local"
    assert_equal "$ADDR_NAME" "agent"
    assert_equal "$ADDR_TENANT" "myteam"
    assert_equal "$ADDR_PROVIDER" "local"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

@test "parse_address: default.local treated as local" {
    parse_address "bot@default.local"
    assert_equal "$ADDR_PROVIDER" "local"
    assert_equal "$ADDR_IS_LOCAL" "true"
}

@test "parse_address: arbitrary .local NOT treated as local" {
    parse_address "bot@evil.notlocal.com"
    assert_equal "$ADDR_IS_LOCAL" "false"
}

@test "parse_address: single-part domain defaults tenant to 'default'" {
    parse_address "user@onlyprovider"
    assert_equal "$ADDR_TENANT" "default"
    assert_equal "$ADDR_PROVIDER" "onlyprovider"
}

# --- build_address ---

@test "build_address: constructs full address" {
    local result
    result=$(build_address "alice" "acme" "aimaestro.local")
    assert_equal "$result" "alice@acme.aimaestro.local"
}

@test "build_address: uses defaults for tenant and provider" {
    local result
    result=$(build_address "alice")
    assert_equal "$result" "alice@default.aimaestro.local"
}

@test "build_address: custom provider" {
    local result
    result=$(build_address "bob" "myco" "crabmail.ai")
    assert_equal "$result" "bob@myco.crabmail.ai"
}
