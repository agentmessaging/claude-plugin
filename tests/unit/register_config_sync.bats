#!/usr/bin/env bats
# =============================================================================
# Tests: registration must leave the agent's own identity consistent
# =============================================================================
#
# Reported from the field (Salesland iCPA, 3Metas): amp-register.sh wrote
# registrations/<provider>.json and IDENTITY.md but never touched config.json,
# so every tool that reads .agent.address kept reporting the PRE-registration
# identity. A correctly registered agent — apiKey issued, registration file
# present, address salesland-dev-3metas@rnd23blocks.aimaestro.local — showed
# @default.local in amp-statusline, amp-identity and amp-inbox.
#
# It looked cosmetic and was not: every place a human would check to confirm
# registration reported that it had not happened.

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "default"
    create_test_keys
    source_amp_helper
}

# The patch amp-register applies on a 2xx, extracted so it can be tested
# without standing up a provider.
apply_registration_to_config() {
    local tenant="$1" address="$2" domain="$3" maestro_url="$4"
    local tmp
    tmp=$(mktemp)
    jq --arg tenant "$tenant" --arg address "$address" \
       --arg domain "$domain" --arg maestro_url "$maestro_url" \
       '.agent.tenant = $tenant
        | .agent.address = $address
        | .provider = ((.provider // {}) + {domain: $domain, maestro_url: $maestro_url})' \
       "$AMP_CONFIG" > "$tmp" && mv "$tmp" "$AMP_CONFIG"
}

@test "registration updates the address every tool reads" {
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -r '.agent.address' "$AMP_CONFIG"
    assert_output "agent@rnd23blocks.aimaestro.local"
}

@test "registration updates the tenant" {
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -r '.agent.tenant' "$AMP_CONFIG"
    assert_output "rnd23blocks"
}

@test "registration records the provider block" {
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -r '.provider.domain' "$AMP_CONFIG"
    assert_output "aimaestro.local"
}

@test "registration PRESERVES the agent id" {
    # Patched surgically rather than through save_config, which rebuilds the
    # object and would drop the id — the same destructive shape as the old
    # load_config auto-fix.
    jq '.agent.id = "aaaabbbb-cccc-dddd-eeee-ffff00001111"' "$AMP_CONFIG" > "${AMP_CONFIG}.t" && mv "${AMP_CONFIG}.t" "$AMP_CONFIG"
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -r '.agent.id' "$AMP_CONFIG"
    assert_output "aaaabbbb-cccc-dddd-eeee-ffff00001111"
}

@test "registration PRESERVES the fingerprint" {
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -r '.agent.fingerprint' "$AMP_CONFIG"
    assert_output "SHA256:testfingerprint123"
}

@test "registration leaves the config valid JSON" {
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    run jq -e '.' "$AMP_CONFIG"
    assert_success
}

@test "load_config reports the registered address afterwards" {
    # The actual symptom: the tools read through load_config.
    apply_registration_to_config "rnd23blocks" "agent@rnd23blocks.aimaestro.local" "aimaestro.local" "http://localhost:23000/api"
    load_config
    [ "$AMP_ADDRESS" = "agent@rnd23blocks.aimaestro.local" ]
    [ "$AMP_TENANT" = "rnd23blocks" ]
}

@test "help documents the /api base for self-hosted providers" {
    # Passing http://localhost:23000 gives a 404 that reads like the provider
    # is down, because the script posts to {API_URL}/v1/register.
    run bash "${SCRIPTS_DIR}/amp-register.sh" --help
    assert_output --partial "/api"
}
