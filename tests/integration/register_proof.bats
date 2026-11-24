#!/usr/bin/env bats
# =============================================================================
# Integration Tests: registering a name that exists proves its key (AMP spec 03)
# =============================================================================
# The provider answers 401 proof_required with {provider, tenant, name,
# fingerprint}; amp_register_request signs
#   "amp-register-proof\n" + ts + "\n" + provider + "\n" + tenant + "\n" + name + "\n" + fingerprint
# and sends the registration again with proof = base64url(signature + ts).
# The stub curl below plays the provider and checks the proof with openssl.

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "alice" "acme"
    create_test_keys
    export OPENSSL_STUB
    OPENSSL_STUB=$(_find_openssl) || skip "No Ed25519-capable OpenSSL available"
    source "${SCRIPTS_DIR}/amp-helper.sh"
    BODY='{"name":"alice","tenant":"acme","public_key":"x","key_algorithm":"Ed25519"}'
}

# <mode>: own (201 at once), proof (401, then checks the proof), othername, 409
stub_provider() {
    local d="${BATS_TEST_TMPDIR}"
    mkdir -p "${d}/bin"
    printf '%s' "$1" > "${d}/mode"
    cp "${AMP_KEYS_DIR}/public.pem" "${d}/pub.pem"
    cat > "${d}/bin/curl" <<'MOCK'
#!/bin/bash
d="$(cd "$(dirname "$0")/.." && pwd)"
body="" prev=""
for a in "$@"; do case "$prev" in -d) body="$a" ;; esac; prev="$a"; done
cat > /dev/null   # headers on stdin
printf '%s\n' "$body" >> "${d}/bodies.log"
mode=$(cat "${d}/mode")
fp="SHA256:$("$OPENSSL_STUB" pkey -pubin -in "${d}/pub.pem" -outform DER | tail -c 32 | "$OPENSSL_STUB" dgst -sha256 -binary | base64 | tr -d '\n')"
challenge() { jq -cn --arg n "${1:-alice}" --arg fp "$fp" '{error:"proof_required",message:"prove it",details:{provider:"acme.aimaestro.local",tenant:"acme",name:$n,fingerprint:$fp}}'; printf '401'; exit 0; }
case "$mode" in
    own) printf '{"api_key":"amp_live_sk_test"}\n201'; exit 0 ;;
    409) printf '{"error":"name_taken","message":"taken"}\n409'; exit 0 ;;
    othername) challenge bob ;;
esac
proof=$(printf '%s' "$body" | jq -r '.proof // empty')
[ -z "$proof" ] && challenge
# base64url -> bytes: 64 signature bytes, then the timestamp
b64=$(printf '%s' "$proof" | tr -- '-_' '+/'); while [ $(( ${#b64} % 4 )) -ne 0 ]; do b64="${b64}="; done
printf '%s' "$b64" | base64 -d > "${d}/proof.bin" 2>/dev/null || printf '%s' "$b64" | base64 -D > "${d}/proof.bin"
head -c 64 "${d}/proof.bin" > "${d}/sig.bin"; ts=$(tail -c +65 "${d}/proof.bin")
printf 'amp-register-proof\n%s\nacme.aimaestro.local\nacme\nalice\n%s' "$ts" "$fp" > "${d}/signed.txt"
if "$OPENSSL_STUB" pkeyutl -verify -pubin -inkey "${d}/pub.pem" -rawin -in "${d}/signed.txt" -sigfile "${d}/sig.bin" >/dev/null 2>&1; then
    printf '{"api_key":"amp_live_sk_proved"}\n201'
else
    printf '{"error":"invalid_proof","message":"no"}\n401'
fi
MOCK
    chmod +x "${d}/bin/curl"
    export PATH="${d}/bin:${PATH}"
}

@test "register_proof: the agent's own session gets a key at once, nothing signed" {
    stub_provider own
    run amp_register_request "http://p.test/api/v1/register" "$BODY"
    assert_success
    assert_output --partial "201"
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/bodies.log")" -eq 1 ]
}

@test "register_proof: answers proof_required with a proof the provider verifies" {
    stub_provider proof
    run amp_register_request "http://p.test/api/v1/register" "$BODY"
    assert_success
    assert_output --partial "amp_live_sk_proved"
    assert_output --partial "201"
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/bodies.log")" -eq 2 ]
    # base64url, no padding
    tail -n1 "${BATS_TEST_TMPDIR}/bodies.log" | jq -re '.proof | test("^[A-Za-z0-9_-]+$")'
}

@test "register_proof: signs nothing when the provider names another agent" {
    stub_provider othername
    run amp_register_request "http://p.test/api/v1/register" "$BODY"
    assert_output --partial "Nothing was signed"
    assert_output --partial "401"
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/bodies.log")" -eq 1 ]
}

@test "register_proof: other answers come back unchanged" {
    stub_provider 409
    run amp_register_request "http://p.test/api/v1/register" "$BODY"
    assert_output --partial "name_taken"
    assert_output --partial "409"
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/bodies.log")" -eq 1 ]
}
