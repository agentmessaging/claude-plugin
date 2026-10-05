#!/usr/bin/env bats
# =============================================================================
# Tests: AFP attachment helpers (afp_validate_ref, afp_attachment_from_ref)
# =============================================================================

D64="sha256:3b2c9f5da87e4f1c8b0a2d6e9f3c7a1b5d8e2f4a6c0b3d7e9f1a4c6d8e0b2a40"

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
    unset SCRIPT_DIR

    # Stub afp scripts: afp-link.sh gives digest and size, afp-ls.sh the content type
    STUBS="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "$STUBS"
    cat > "${STUBS}/afp-link.sh" <<STUB
#!/bin/bash
echo "\$@" >> "${BATS_TEST_TMPDIR}/afp-link.calls"
if [ -n "\$AFP_STUB_FAIL" ]; then
    echo '{"ok":false,"error":{"code":"not_found","message":"no such object"}}'
    exit 1
fi
echo '{"ok":true,"ref":"'"\$1"'","digest":"${D64}","size":1827341,"endpoint":"http://100.76.17.128:3900","url":"http://100.76.17.128:3900/b/x?X-Amz-Signature=abc","url_expires":"2026-10-05T00:00:00Z"}'
STUB
    cat > "${STUBS}/afp-ls.sh" <<'STUB'
#!/bin/bash
echo '{"ok":true,"items":[{"ref":"afp://shared/2026/10/report.pdf","size":1827341,"content_type":"application/pdf"}],"truncated":false}'
STUB
    chmod +x "${STUBS}/afp-link.sh" "${STUBS}/afp-ls.sh"
    export PATH="${STUBS}:${PATH}"
}

# --- afp_validate_ref ---

@test "afp_validate_ref: accepts a normal reference" {
    run afp_validate_ref "afp://shared/2026/10/report.pdf"
    assert_success
}

@test "afp_validate_ref: rejects .. segments" {
    run afp_validate_ref "afp://shared/a/../b"
    assert_failure
    run afp_validate_ref "afp://shared/../etc/passwd"
    assert_failure
}

@test "afp_validate_ref: rejects empty segments, trailing slash and dot segments" {
    run afp_validate_ref "afp://shared/a//b"
    assert_failure
    run afp_validate_ref "afp://shared/a/"
    assert_failure
    run afp_validate_ref "afp://shared/a/./b"
    assert_failure
}

@test "afp_validate_ref: rejects encoded separators and backslashes" {
    run afp_validate_ref "afp://shared/a%2Fb"
    assert_failure
    run afp_validate_ref "afp://shared/a%2fb"
    assert_failure
    run afp_validate_ref 'afp://shared/a\b'
    assert_failure
}

@test "afp_validate_ref: rejects bad space names and other schemes" {
    run afp_validate_ref "afp://Shared/a"
    assert_failure
    run afp_validate_ref "afp://-shared/a"
    assert_failure
    run afp_validate_ref "https://shared/a"
    assert_failure
    run afp_validate_ref "afp://shared"
    assert_failure
}

@test "afp_validate_ref: rejects paths over 512 characters" {
    long=$(printf 'a%.0s' $(seq 1 513))
    run afp_validate_ref "afp://shared/${long}"
    assert_failure
}

# --- afp_attachment_from_ref ---

@test "afp_attachment_from_ref: bare ref builds an afp attachment" {
    run afp_attachment_from_ref "afp://shared/2026/10/report.pdf"
    assert_success
    assert_equal "$(echo "$output" | jq -r .storage)" "afp"
    assert_equal "$(echo "$output" | jq -r .ref)" "afp://shared/2026/10/report.pdf"
    assert_equal "$(echo "$output" | jq -r .digest)" "$D64"
    assert_equal "$(echo "$output" | jq -r .size)" "1827341"
    assert_equal "$(echo "$output" | jq -r .filename)" "report.pdf"
    assert_equal "$(echo "$output" | jq -r .content_type)" "application/pdf"
    assert_equal "$(echo "$output" | jq -r .endpoint)" "http://100.76.17.128:3900"
}

@test "afp_attachment_from_ref: has none of the provider-only fields" {
    run afp_attachment_from_ref "afp://shared/2026/10/report.pdf"
    assert_success
    for f in id scan_status uploaded_at expires_at; do
        assert_equal "$(echo "$output" | jq --arg f "$f" 'has($f)')" "false"
    done
}

@test "afp_attachment_from_ref: strips the download url unless a link is asked for" {
    run afp_attachment_from_ref "afp://shared/2026/10/report.pdf"
    assert_success
    assert_equal "$(echo "$output" | jq 'has("url")')" "false"
    run afp_attachment_from_ref "afp://shared/2026/10/report.pdf" true
    assert_success
    assert_equal "$(echo "$output" | jq -r '.url | startswith("http")')" "true"
    grep -q -- "--ttl 1h" "${BATS_TEST_TMPDIR}/afp-link.calls"
}

@test "afp_attachment_from_ref: a complete reference object needs no afp scripts" {
    rm -f "${STUBS}/afp-link.sh"
    obj='{"ref":"afp://shared/x/data.json","digest":"'"$D64"'","size":10,"content_type":"application/json"}'
    run afp_attachment_from_ref "$obj"
    assert_success
    assert_equal "$(echo "$output" | jq -r .filename)" "data.json"
    assert_equal "$(echo "$output" | jq -r .content_type)" "application/json"
}

@test "afp_attachment_from_ref: a url given in a reference object is kept" {
    obj='{"ref":"afp://shared/x/data.json","digest":"'"$D64"'","size":10,"url":"https://files.example.net/x?sig=1"}'
    run afp_attachment_from_ref "$obj"
    assert_success
    assert_equal "$(echo "$output" | jq -r .url)" "https://files.example.net/x?sig=1"
}

@test "afp_attachment_from_ref: rejects a bad digest" {
    obj='{"ref":"afp://shared/x/data.json","digest":"sha256:abc","size":10}'
    run afp_attachment_from_ref "$obj"
    assert_failure
    assert_output --partial "digest"
    obj='{"ref":"afp://shared/x/data.json","digest":"md5:3b2c9f5da87e4f1c8b0a2d6e9f3c7a1b5d8e2f4a6c0b3d7e9f1a4c6d8e0b2a40","size":10}'
    run afp_attachment_from_ref "$obj"
    assert_failure
}

@test "afp_attachment_from_ref: rejects a bad size" {
    obj='{"ref":"afp://shared/x/data.json","digest":"'"$D64"'","size":"ten"}'
    run afp_attachment_from_ref "$obj"
    assert_failure
    assert_output --partial "size"
}

@test "afp_attachment_from_ref: rejects a traversal reference, even inside an object" {
    run afp_attachment_from_ref "afp://shared/../x"
    assert_failure
    assert_output --partial "Invalid AFP reference"
    obj='{"ref":"afp://shared/a%2Fb","digest":"'"$D64"'","size":10}'
    run afp_attachment_from_ref "$obj"
    assert_failure
}

@test "afp_attachment_from_ref: rejects a non-http endpoint or link" {
    obj='{"ref":"afp://shared/x","digest":"'"$D64"'","size":10,"endpoint":"file:///etc/passwd"}'
    run afp_attachment_from_ref "$obj"
    assert_failure
    obj='{"ref":"afp://shared/x","digest":"'"$D64"'","size":10,"url":"javascript:alert(1)"}'
    run afp_attachment_from_ref "$obj"
    assert_failure
}

@test "afp_attachment_from_ref: invalid JSON fails" {
    run afp_attachment_from_ref '{"ref":'
    assert_failure
    assert_output --partial "not a valid JSON object"
}

@test "afp_attachment_from_ref: missing afp scripts gives a clear error for a bare ref" {
    rm -f "${STUBS}/afp-link.sh"
    PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" run afp_attachment_from_ref "afp://shared/x/data.json"
    assert_failure
    assert_output --partial "afp-link.sh not found"
}

@test "afp_attachment_from_ref: an unreadable object fails clearly" {
    AFP_STUB_FAIL=1 run afp_attachment_from_ref "afp://shared/x/data.json"
    assert_failure
    assert_output --partial "could not read"
}

@test "afp_attachment_from_ref: filename is sanitized" {
    obj='{"ref":"afp://shared/x/a.txt","digest":"'"$D64"'","size":1,"filename":"../../evil name?.txt"}'
    run afp_attachment_from_ref "$obj"
    assert_success
    assert_equal "$(echo "$output" | jq -r .filename)" "evil_name_.txt"
}
