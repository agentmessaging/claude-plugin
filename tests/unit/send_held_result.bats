#!/usr/bin/env bats
# =============================================================================
# Tests: what amp-send prints when a provider holds a message for approval (202, status "held")
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

@test "a sent message keeps the usual title" {
    run amp_send_title "delivered" "AI Maestro"
    assert_success
    assert_output "✅ Message sent via AI Maestro"
}

@test "a held message says it is held, not sent" {
    run amp_send_title "held" "AI Maestro"
    assert_success
    assert_output "⏸  Message held for approval via AI Maestro"
}

@test "a held message prints the provider's reason" {
    body='{"error":"approval_pending","status":"held","message":"Held for approval by Alice (request apr-1, expires 2026-11-20 14:30 UTC)"}'
    run amp_send_held_reason "held" "$body"
    assert_success
    assert_output "  Held:     Held for approval by Alice (request apr-1, expires 2026-11-20 14:30 UTC)"
}

@test "nothing extra for a message that was not held" {
    run amp_send_held_reason "delivered" '{"status":"delivered","message":"ok"}'
    assert_success
    assert_output ""
}

@test "a held answer without a reason prints nothing extra" {
    run amp_send_held_reason "held" '{"status":"held"}'
    assert_success
    assert_output ""
}
