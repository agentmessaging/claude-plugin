#!/usr/bin/env bats
# =============================================================================
# Integration Tests: --attach-afp on send, and AFP attachments on read/inbox/download
# =============================================================================

D64="sha256:3b2c9f5da87e4f1c8b0a2d6e9f3c7a1b5d8e2f4a6c0b3d7e9f1a4c6d8e0b2a40"

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "sender" "testorg"
    create_test_keys

    local recipient_uuid="test-uuid-alice"
    RECIPIENT_DIR="${HOME}/.agent-messaging/agents/${recipient_uuid}"
    mkdir -p "${RECIPIENT_DIR}/messages/inbox" "${RECIPIENT_DIR}/keys"
    cat > "${RECIPIENT_DIR}/config.json" << 'EOF'
{"version":"1.1","agent":{"name":"alice","tenant":"testorg","address":"alice@testorg.aimaestro.local"}}
EOF
    echo '{"alice":"test-uuid-alice"}' > "${HOME}/.agent-messaging/agents/.index.json"
    create_local_registration "http://localhost:99999/api/v1" "test-api-key"

    STUBS="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "$STUBS"
    cat > "${STUBS}/afp-link.sh" <<STUB
#!/bin/bash
echo '{"ok":true,"ref":"'"\$1"'","digest":"${D64}","size":2048,"endpoint":"http://100.76.17.128:3900","url":"http://100.76.17.128:3900/b/x?X-Amz-Signature=abc"}'
STUB
    cat > "${STUBS}/afp-ls.sh" <<'STUB'
#!/bin/bash
echo '{"ok":true,"items":[{"ref":"afp://shared/2026/10/report.pdf","content_type":"application/pdf"}]}'
STUB
    chmod +x "${STUBS}/afp-link.sh" "${STUBS}/afp-ls.sh"
    export PATH="${STUBS}:${PATH}"
}

delivered() {
    find "${RECIPIENT_DIR}/messages/inbox" -name "msg_*.json" | head -1
}

@test "send --attach-afp: payload carries an afp attachment" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Report" "See file" --attach-afp afp://shared/2026/10/report.pdf
    assert_success
    assert_output --partial "AFP reference: afp://shared/2026/10/report.pdf"
    local f; f=$(delivered)
    [ -n "$f" ]
    assert_equal "$(jq -r '.payload.attachments | length' "$f")" "1"
    assert_equal "$(jq -r '.payload.attachments[0].storage' "$f")" "afp"
    assert_equal "$(jq -r '.payload.attachments[0].ref' "$f")" "afp://shared/2026/10/report.pdf"
    assert_equal "$(jq -r '.payload.attachments[0].digest' "$f")" "$D64"
    assert_equal "$(jq -r '.payload.attachments[0] | has("id") or has("scan_status") or has("uploaded_at") or has("expires_at") or has("local_path")' "$f")" "false"
    assert_equal "$(jq -r '.payload.attachments[0] | has("url")' "$f")" "false"
}

@test "send --attach-afp --afp-link: includes a download link" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Report" "See file" --attach-afp afp://shared/2026/10/report.pdf --afp-link
    assert_success
    assert_equal "$(jq -r '.payload.attachments[0].url | startswith("http")' "$(delivered)")" "true"
}

@test "send --attach-afp: a reference object is accepted" {
    obj='{"ref":"afp://shared/x/data.json","digest":"'"$D64"'","size":10,"content_type":"application/json"}'
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Data" "See file" --attach-afp "$obj"
    assert_success
    assert_equal "$(jq -r '.payload.attachments[0].content_type' "$(delivered)")" "application/json"
}

@test "send --attach-afp: the message is still signed" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Signed" "body" --attach-afp afp://shared/2026/10/report.pdf
    assert_success
    local f; f=$(delivered)
    local sig; sig=$(jq -r '.envelope.signature' "$f")
    [ -n "$sig" ] && [ "$sig" != "null" ]
}

@test "send --attach-afp: a traversal reference is refused and nothing is delivered" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Bad" "body" --attach-afp "afp://shared/../x"
    assert_failure
    assert_output --partial "Invalid AFP reference"
    [ -z "$(delivered)" ]
}

@test "send --attach-afp: an encoded separator is refused" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Bad" "body" --attach-afp "afp://shared/a%2Fb"
    assert_failure
    [ -z "$(delivered)" ]
}

@test "send --attach-afp: a bad digest in a reference object is refused" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Bad" "body" --attach-afp '{"ref":"afp://shared/x","digest":"sha256:zz","size":1}'
    assert_failure
    [ -z "$(delivered)" ]
}

@test "send: more than 10 AFP attachments is allowed (the limit is for provider uploads)" {
    args=()
    for i in $(seq 1 12); do args+=(--attach-afp "afp://shared/f${i}.txt"); done
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Many" "body" "${args[@]}"
    assert_success
    assert_equal "$(jq -r '.payload.attachments | length' "$(delivered)")" "12"
}

@test "send: --attach and --attach-afp can be mixed" {
    rm -f "${AMP_DIR}/registrations/aimaestro.local.json"   # no upload API: provider files get local metadata
    echo "hello" > "${BATS_TEST_TMPDIR}/note.txt"
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Mixed" "body" --attach "${BATS_TEST_TMPDIR}/note.txt" --attach-afp afp://shared/2026/10/report.pdf
    assert_success
    local f; f=$(delivered)
    assert_equal "$(jq -r '.payload.attachments | length' "$f")" "2"
    assert_equal "$(jq -r '[.payload.attachments[] | select(.storage == "afp")] | length' "$f")" "1"
    # the provider attachment keeps its provider shape
    assert_equal "$(jq -r '[.payload.attachments[] | select(.storage != "afp")][0] | has("id") and has("scan_status")' "$f")" "true"
}

@test "send: without --attach-afp nothing changes (no storage field on provider attachments)" {
    rm -f "${AMP_DIR}/registrations/aimaestro.local.json"
    echo "hello" > "${BATS_TEST_TMPDIR}/note.txt"
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Plain" "body" --attach "${BATS_TEST_TMPDIR}/note.txt"
    assert_success
    assert_equal "$(jq -r '.payload.attachments[0] | has("storage")' "$(delivered)")" "false"
}

# --- receiving side: a message with an AFP attachment sits in the inbox ---

make_afp_message() {
    create_inbox_message "msg_2000_afp" "alice@testorg.aimaestro.local" "AFP msg" "a file for you"
    local f
    f=$(find "${AMP_DIR}/messages/inbox" -name "msg_2000_afp.json" | head -1)
    jq --arg d "$D64" --arg ref "${1:-afp://shared/2026/10/report.pdf}" \
        '.payload.attachments = [{storage:"afp",filename:"report.pdf",content_type:"application/pdf",size:2048,digest:$d,ref:$ref}]' \
        "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

@test "read: shows the AFP reference and the afp-get command" {
    make_afp_message
    run bash "${SCRIPTS_DIR}/amp-read.sh" "msg_2000_afp"
    assert_success
    assert_output --partial "AFP reference: afp://shared/2026/10/report.pdf"
    assert_output --partial "afp-get.sh afp://shared/2026/10/report.pdf"
    refute_output --partial "ID: null"
    refute_output --partial "amp-download msg_2000_afp --all"
}

@test "read: a malformed AFP reference from the sender is not shown as a command" {
    make_afp_message 'afp://shared/../../etc/passwd; rm -rf ~'
    run bash "${SCRIPTS_DIR}/amp-read.sh" "msg_2000_afp"
    assert_success
    refute_output --partial "afp-get.sh afp://"
    assert_output --partial "do not fetch"
}

@test "inbox: counts AFP references separately" {
    make_afp_message
    run bash "${SCRIPTS_DIR}/amp-inbox.sh"
    assert_success
    assert_output --partial "[1 AFP ref(s)]"
    refute_output --partial "file(s)"
}

@test "download --all: AFP-only message prints the hint and exits 0" {
    make_afp_message
    run bash "${SCRIPTS_DIR}/amp-download.sh" "msg_2000_afp" --all
    assert_success
    assert_output --partial "afp-get.sh afp://shared/2026/10/report.pdf"
    assert_output --partial "No provider attachments to download"
}

@test "download --all: AFP references are skipped, provider ones are still downloaded" {
    make_afp_message
    local f d
    f=$(find "${AMP_DIR}/messages/inbox" -name "msg_2000_afp.json" | head -1)
    mkdir -p "${AMP_DIR}/attachments/att_1_aa"
    printf 'hello\n' > "${AMP_DIR}/attachments/att_1_aa/x.txt"
    d="sha256:$(shasum -a 256 "${AMP_DIR}/attachments/att_1_aa/x.txt" | cut -d' ' -f1)"
    jq --arg d "$d" '.payload.attachments += [{id:"att_1_aa",filename:"x.txt",content_type:"text/plain",size:6,digest:$d,url:null,scan_status:"basic_clean"}]' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    run bash "${SCRIPTS_DIR}/amp-download.sh" "msg_2000_afp" --all
    assert_success
    assert_output --partial "afp-get.sh afp://shared/2026/10/report.pdf"
    assert_output --partial "Saved:"
    assert_output --partial "1 downloaded, 0 failed"
    assert_output --partial "1 AFP reference(s) skipped"
}
