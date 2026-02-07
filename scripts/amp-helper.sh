#!/bin/bash
# =============================================================================
# AMP Helper Functions
# Agent Messaging Protocol - Core utilities for all AMP scripts
# =============================================================================
#
# This file provides common functions for:
# - Configuration management
# - Key generation and signing
# - Message creation and storage
# - Provider routing (local vs external)
#
# Storage: ~/.agent-messaging/
# =============================================================================

set -e

# Source security module
SCRIPT_DIR_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR_HELPER}/amp-security.sh" ]; then
    source "${SCRIPT_DIR_HELPER}/amp-security.sh"
fi

# =============================================================================
# OpenSSL Auto-Detection
# =============================================================================
# macOS ships with LibreSSL which doesn't support Ed25519.
# We auto-detect a compatible OpenSSL binary (Homebrew or system).

_detect_openssl() {
    # Homebrew paths (Intel Mac, Apple Silicon, Linux linuxbrew)
    local candidates=(
        "/usr/local/opt/openssl@3/bin/openssl"
        "/opt/homebrew/opt/openssl@3/bin/openssl"
        "/usr/local/opt/openssl/bin/openssl"
        "/opt/homebrew/opt/openssl/bin/openssl"
        "/home/linuxbrew/.linuxbrew/opt/openssl@3/bin/openssl"
    )

    # Test system openssl first (fastest path - works on Linux)
    if command -v openssl &>/dev/null; then
        if openssl genpkey -algorithm Ed25519 2>/dev/null | grep -q "PRIVATE KEY"; then
            echo "openssl"
            return 0
        fi
    fi

    # Search Homebrew paths
    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            if "$candidate" genpkey -algorithm Ed25519 2>/dev/null | grep -q "PRIVATE KEY"; then
                echo "$candidate"
                return 0
            fi
        fi
    done

    # Nothing found
    echo ""
    return 1
}

# Detect once and cache
OPENSSL_BIN=$(_detect_openssl)

if [ -z "$OPENSSL_BIN" ]; then
    echo "Error: No Ed25519-capable OpenSSL found." >&2
    echo "" >&2
    echo "macOS ships with LibreSSL which lacks Ed25519 support." >&2
    echo "Install OpenSSL 3 via Homebrew:" >&2
    echo "  brew install openssl@3" >&2
    echo "" >&2
    exit 1
fi

# Configuration
#
# Per-Agent Isolation:
#   Each agent gets its own AMP directory at ~/.agent-messaging/agents/<name>/
#   This ensures inboxes, sent folders, keys, and config are completely isolated.
#
# Resolution order for AMP_DIR:
#   1. Explicit AMP_DIR env var (set by AI Maestro wake/create routes)
#   2. Auto-detect from agent name → ~/.agent-messaging/agents/<name>/
#      If the directory doesn't exist, it is auto-created.
#
AMP_AGENTS_BASE="${HOME}/.agent-messaging/agents"

if [ -z "${AMP_DIR:-}" ]; then
    _amp_agent_name=""

    # Try CLAUDE_AGENT_NAME env var first (set by AI Maestro per-session)
    if [ -n "${CLAUDE_AGENT_NAME:-}" ]; then
        _amp_agent_name="${CLAUDE_AGENT_NAME}"
    # Fallback: tmux session name (strip _N multi-session suffix)
    elif [ -n "${TMUX:-}" ]; then
        _amp_agent_name=$(tmux display-message -p '#S' 2>/dev/null || true)
        _amp_agent_name="${_amp_agent_name%_[0-9]*}"
    fi

    if [ -n "$_amp_agent_name" ]; then
        AMP_DIR="${AMP_AGENTS_BASE}/${_amp_agent_name}"
        # Auto-create per-agent directory if it doesn't exist
        if [ ! -d "$AMP_DIR" ]; then
            mkdir -p "${AMP_DIR}/keys"
            mkdir -p "${AMP_DIR}/messages/inbox"
            mkdir -p "${AMP_DIR}/messages/sent"
            mkdir -p "${AMP_DIR}/registrations"
            chmod 700 "${AMP_DIR}/keys"
        fi
    else
        echo "Error: Cannot determine agent name." >&2
        echo "Set CLAUDE_AGENT_NAME or run inside a tmux session." >&2
        exit 1
    fi
    unset _amp_agent_name
fi

AMP_CONFIG="${AMP_DIR}/config.json"
AMP_KEYS_DIR="${AMP_DIR}/keys"
AMP_MESSAGES_DIR="${AMP_DIR}/messages"
AMP_INBOX_DIR="${AMP_MESSAGES_DIR}/inbox"
AMP_SENT_DIR="${AMP_MESSAGES_DIR}/sent"
AMP_REGISTRATIONS_DIR="${AMP_DIR}/registrations"

# AI Maestro connection
AMP_MAESTRO_URL="${AMP_MAESTRO_URL:-http://localhost:23000}"

# Provider domain (AMP v1)
AMP_PROVIDER_DOMAIN="aimaestro.local"
AMP_LOCAL_DOMAIN="${AMP_PROVIDER_DOMAIN}"

# =============================================================================
# Directory Setup
# =============================================================================

ensure_amp_dirs() {
    mkdir -p "${AMP_DIR}"
    mkdir -p "${AMP_KEYS_DIR}"
    mkdir -p "${AMP_MESSAGES_DIR}/inbox"
    mkdir -p "${AMP_MESSAGES_DIR}/sent"
    mkdir -p "${AMP_REGISTRATIONS_DIR}"

    # Secure permissions for keys directory
    chmod 700 "${AMP_KEYS_DIR}"
}

# =============================================================================
# Organization (AI Maestro Integration)
# =============================================================================

# Get organization from AI Maestro
# Returns organization name or empty string if not set
# Falls back to "default" if AI Maestro is unreachable (for offline use)
get_organization() {
    local response
    local org

    # First check if we have a cached org in config
    if [ -f "${AMP_CONFIG}" ]; then
        local cached_tenant
        cached_tenant=$(jq -r '.agent.tenant // empty' "${AMP_CONFIG}" 2>/dev/null)
        if [ -n "$cached_tenant" ] && [ "$cached_tenant" != "default" ]; then
            echo "$cached_tenant"
            return 0
        fi
    fi

    # Try to fetch from AI Maestro
    response=$(curl -s --connect-timeout 2 "${AMP_MAESTRO_URL}/api/organization" 2>/dev/null) || true

    if [ -n "$response" ]; then
        org=$(echo "$response" | jq -r '.organization // empty' 2>/dev/null)
        if [ -n "$org" ] && [ "$org" != "null" ]; then
            echo "$org"
            return 0
        fi
    fi

    # Fallback for offline use - return "default" instead of failing
    echo "default"
    return 0
}

# Check if organization is set in AI Maestro
is_organization_set() {
    local org
    org=$(get_organization 2>/dev/null)
    [ -n "$org" ]
}

# =============================================================================
# Identity File Management
# =============================================================================

# Create or update IDENTITY.md file
# This file helps agents rediscover their identity after context reset
# Supports multiple addresses across providers
create_identity_file() {
    local name="$1"
    local tenant="$2"
    local primary_address="$3"
    local fingerprint="$4"

    local identity_file="${AMP_DIR}/IDENTITY.md"
    local updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build addresses section - collect all registered addresses
    local addresses_section=""
    local all_addresses="${primary_address}"
    local provider_count=0

    # Start with primary/local address
    addresses_section="| **Local (AI Maestro)** | \`${primary_address}\` | Primary |"

    # Check for external provider registrations
    if [ -d "${AMP_REGISTRATIONS_DIR}" ]; then
        # Use find to avoid glob expansion issues when directory is empty
        while IFS= read -r reg_file; do
            [ -z "$reg_file" ] && continue
            if [ -f "$reg_file" ]; then
                local provider=$(jq -r '.provider // empty' "$reg_file" 2>/dev/null)
                local ext_address=$(jq -r '.address // empty' "$reg_file" 2>/dev/null)

                if [ -n "$ext_address" ] && [ -n "$provider" ]; then
                    provider_count=$((provider_count + 1))
                    addresses_section="${addresses_section}
| **${provider}** | \`${ext_address}\` | External |"
                    all_addresses="${all_addresses}, ${ext_address}"
                fi
            fi
        done < <(find "${AMP_REGISTRATIONS_DIR}" -maxdepth 1 -name "*.json" -type f 2>/dev/null)
    fi

    # Build a concise summary for CLAUDE.md
    local claude_md_snippet="This agent uses AMP. Primary: \`${primary_address}\`"
    if [ "$provider_count" -gt 0 ]; then
        claude_md_snippet="${claude_md_snippet} (+${provider_count} external)"
    fi

    cat > "${identity_file}" << EOF
# Agent Messaging Protocol (AMP) Identity

This agent is configured for inter-agent messaging using AMP.

## Core Identity

| Field | Value |
|-------|-------|
| **Name** | ${name} |
| **Tenant** | ${tenant} |
| **Fingerprint** | ${fingerprint} |
| **Last Updated** | ${updated_at} |

## My Addresses

You have **$((provider_count + 1)) address(es)** - use the appropriate one based on recipient:

| Provider | Address | Type |
|----------|---------|------|
${addresses_section}

**Which address to use:**
- Local address → for agents in your AI Maestro mesh
- External address → for agents on that specific provider

## Files Location

| File | Path |
|------|------|
| Identity File | ${identity_file} |
| Private Key | ${AMP_KEYS_DIR}/private.pem |
| Public Key | ${AMP_KEYS_DIR}/public.pem |
| Config | ${AMP_CONFIG} |
| Registrations | ${AMP_REGISTRATIONS_DIR}/ |
| Inbox | ${AMP_INBOX_DIR}/ |
| Sent | ${AMP_SENT_DIR}/ |

## Quick Commands

\`\`\`bash
# Check your identity (run this first!)
amp-identity.sh

# Check your inbox
amp-inbox.sh

# Send a message (local)
amp-send.sh alice "Subject" "Message body"

# Send a message (external - uses your external address automatically)
amp-send.sh bob@acme.crabmail.ai "Subject" "Message body"

# Read a specific message
amp-read.sh <message-id>

# Reply to a message
amp-reply.sh <message-id> "Reply message"

# Check full status
amp-status.sh

# Register with new provider
amp-register.sh --provider crabmail.ai --tenant ${tenant}
\`\`\`

## For Claude Code Agents

If you are a Claude Code agent and want to persist your AMP identity in your project,
you can add the following line to your project's CLAUDE.md:

\`\`\`markdown
## Agent Messaging
${claude_md_snippet}
Run \`cat ~/.agent-messaging/IDENTITY.md\` for details or use the \`agent-messaging\` skill.
\`\`\`

## Skill Usage

Use natural language with the \`agent-messaging\` skill:
- "Check my messages"
- "Send a message to alice about the deployment"
- "Reply to the last message"
- "What's my AMP identity?"

---
*Generated by AMP on ${updated_at}*
*Addresses: ${all_addresses}*
EOF

    chmod 644 "${identity_file}"
    echo "${identity_file}"
}

# Update IDENTITY.md after registration changes
# Call this after amp-register to refresh the file
update_identity_file() {
    if ! is_initialized; then
        return 1
    fi

    load_config

    create_identity_file "$AMP_AGENT_NAME" "$AMP_TENANT" "$AMP_ADDRESS" "$AMP_FINGERPRINT"
}

# Read identity from config.json and registrations
# Returns identity info as JSON including all addresses
get_identity() {
    # First try config.json (authoritative)
    if [ -f "${AMP_CONFIG}" ]; then
        local name=$(jq -r '.agent.name // empty' "${AMP_CONFIG}" 2>/dev/null)
        local tenant=$(jq -r '.agent.tenant // empty' "${AMP_CONFIG}" 2>/dev/null)
        local address=$(jq -r '.agent.address // empty' "${AMP_CONFIG}" 2>/dev/null)
        local fingerprint=$(jq -r '.agent.fingerprint // empty' "${AMP_CONFIG}" 2>/dev/null)

        if [ -n "$name" ]; then
            # Build addresses array with primary
            local addresses_json="[{\"provider\": \"local\", \"address\": \"${address}\", \"type\": \"primary\"}]"

            # Add external addresses from registrations
            if [ -d "${AMP_REGISTRATIONS_DIR}" ]; then
                while IFS= read -r reg_file; do
                    [ -z "$reg_file" ] && continue
                    if [ -f "$reg_file" ]; then
                        local provider=$(jq -r '.provider // empty' "$reg_file" 2>/dev/null)
                        local ext_address=$(jq -r '.address // empty' "$reg_file" 2>/dev/null)

                        if [ -n "$ext_address" ] && [ -n "$provider" ]; then
                            addresses_json=$(echo "$addresses_json" | jq \
                                --arg provider "$provider" \
                                --arg address "$ext_address" \
                                '. + [{provider: $provider, address: $address, type: "external"}]')
                        fi
                    fi
                done < <(find "${AMP_REGISTRATIONS_DIR}" -maxdepth 1 -name "*.json" -type f 2>/dev/null)
            fi

            jq -n \
                --arg name "$name" \
                --arg tenant "$tenant" \
                --arg primary_address "$address" \
                --arg fingerprint "$fingerprint" \
                --arg config_path "${AMP_CONFIG}" \
                --arg identity_path "${AMP_DIR}/IDENTITY.md" \
                --arg keys_dir "${AMP_KEYS_DIR}" \
                --argjson addresses "$addresses_json" \
                '{
                    initialized: true,
                    name: $name,
                    tenant: $tenant,
                    fingerprint: $fingerprint,
                    primary_address: $primary_address,
                    addresses: $addresses,
                    address_count: ($addresses | length),
                    paths: {
                        config: $config_path,
                        identity: $identity_path,
                        keys: $keys_dir
                    }
                }'
            return 0
        fi
    fi

    # Not initialized
    jq -n '{initialized: false, message: "AMP not initialized. Run: amp-init --auto"}'
    return 1
}

# Check identity and print summary (for agent context recovery)
check_identity() {
    local format="${1:-text}"  # text or json

    if ! is_initialized; then
        if [ "$format" = "json" ]; then
            echo '{"initialized": false, "message": "AMP not initialized. Run: amp-init --auto"}'
        else
            echo "❌ AMP not initialized"
            echo ""
            echo "Run 'amp-init --auto' to set up your agent identity."
        fi
        return 1
    fi

    load_config

    if [ "$format" = "json" ]; then
        get_identity
    else
        echo "✅ AMP Identity Verified"
        echo ""
        echo "  Name:        ${AMP_AGENT_NAME}"
        echo "  Tenant:      ${AMP_TENANT}"
        echo "  Fingerprint: ${AMP_FINGERPRINT}"
        echo ""
        echo "  Addresses:"
        echo "    Local:     ${AMP_ADDRESS}"

        # Show external addresses
        local ext_count=0
        if [ -d "${AMP_REGISTRATIONS_DIR}" ]; then
            while IFS= read -r reg_file; do
                [ -z "$reg_file" ] && continue
                if [ -f "$reg_file" ]; then
                    local provider=$(jq -r '.provider // empty' "$reg_file" 2>/dev/null)
                    local ext_address=$(jq -r '.address // empty' "$reg_file" 2>/dev/null)

                    if [ -n "$ext_address" ] && [ -n "$provider" ]; then
                        printf "    %-10s %s\n" "${provider}:" "${ext_address}"
                        ext_count=$((ext_count + 1))
                    fi
                fi
            done < <(find "${AMP_REGISTRATIONS_DIR}" -maxdepth 1 -name "*.json" -type f 2>/dev/null)
        fi

        echo ""
        echo "  Identity file: ${AMP_DIR}/IDENTITY.md"

        if [ "$ext_count" -eq 0 ]; then
            echo ""
            echo "  Tip: Register with external providers to message agents globally:"
            echo "       amp-register.sh --provider crabmail.ai --tenant ${AMP_TENANT}"
        fi

        echo ""
        echo "Commands: amp-inbox.sh | amp-send.sh | amp-status.sh"
    fi
    return 0
}

# Get organization or fail with helpful message
require_organization() {
    local org
    org=$(get_organization 2>/dev/null)

    if [ -z "$org" ]; then
        echo "Error: Organization not configured in AI Maestro." >&2
        echo "" >&2
        echo "Before using AMP, you must configure your organization:" >&2
        echo "  1. Open AI Maestro at ${AMP_MAESTRO_URL}" >&2
        echo "  2. Complete the organization setup" >&2
        echo "" >&2
        return 1
    fi

    echo "$org"
}

# =============================================================================
# Configuration
# =============================================================================

# Load or create config
load_config() {
    if [ ! -f "${AMP_CONFIG}" ]; then
        return 1
    fi

    # Export config values
    AMP_AGENT_NAME=$(jq -r '.agent.name // empty' "${AMP_CONFIG}" 2>/dev/null)
    AMP_TENANT=$(jq -r '.agent.tenant // "default"' "${AMP_CONFIG}" 2>/dev/null)
    AMP_ADDRESS=$(jq -r '.agent.address // empty' "${AMP_CONFIG}" 2>/dev/null)
    AMP_FINGERPRINT=$(jq -r '.agent.fingerprint // empty' "${AMP_CONFIG}" 2>/dev/null)

    if [ -z "${AMP_AGENT_NAME}" ]; then
        return 1
    fi

    return 0
}

# Save config
save_config() {
    local name="$1"
    local tenant="${2:-default}"
    local fingerprint="$3"

    # Build address: name@tenant.aimaestro.local
    local address="${name}@${tenant}.${AMP_PROVIDER_DOMAIN}"

    jq -n \
        --arg name "$name" \
        --arg tenant "$tenant" \
        --arg address "$address" \
        --arg fingerprint "$fingerprint" \
        --arg provider_domain "$AMP_PROVIDER_DOMAIN" \
        --arg maestro_url "$AMP_MAESTRO_URL" \
        --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            version: "1.1",
            agent: {
                name: $name,
                tenant: $tenant,
                address: $address,
                fingerprint: $fingerprint,
                createdAt: $created
            },
            provider: {
                domain: $provider_domain,
                maestro_url: $maestro_url
            }
        }' > "${AMP_CONFIG}"

    echo "${address}"
}

# Check if initialized
is_initialized() {
    [ -f "${AMP_CONFIG}" ] && [ -f "${AMP_KEYS_DIR}/private.pem" ]
}

# =============================================================================
# Key Management
# =============================================================================

# Generate Ed25519 keypair
generate_keypair() {
    ensure_amp_dirs

    local private_key="${AMP_KEYS_DIR}/private.pem"
    local public_key="${AMP_KEYS_DIR}/public.pem"

    # Generate private key
    $OPENSSL_BIN genpkey -algorithm Ed25519 -out "${private_key}" 2>/dev/null
    chmod 600 "${private_key}"

    # Extract public key
    $OPENSSL_BIN pkey -in "${private_key}" -pubout -out "${public_key}" 2>/dev/null
    chmod 644 "${public_key}"

    # Calculate fingerprint
    local fingerprint
    fingerprint=$($OPENSSL_BIN pkey -in "${private_key}" -pubout -outform DER 2>/dev/null | \
                  $OPENSSL_BIN dgst -sha256 -binary | base64)

    echo "SHA256:${fingerprint}"
}

# Get public key hex (for registration)
get_public_key_hex() {
    local public_key="${AMP_KEYS_DIR}/public.pem"

    if [ ! -f "${public_key}" ]; then
        echo "Error: No public key found" >&2
        return 1
    fi

    # Extract raw public key bytes and convert to hex
    $OPENSSL_BIN pkey -pubin -in "${public_key}" -outform DER 2>/dev/null | \
        tail -c 32 | xxd -p | tr -d '\n'
}

# Sign a message
sign_message() {
    local message="$1"
    local private_key="${AMP_KEYS_DIR}/private.pem"

    if [ ! -f "${private_key}" ]; then
        echo "Error: No private key found" >&2
        return 1
    fi

    # Use temporary files for signing (OpenSSL 3.x has issues with Ed25519 + stdin)
    local tmp_msg=$(mktemp)
    local tmp_sig=$(mktemp)

    echo -n "${message}" > "$tmp_msg"
    # Note: Ed25519 keys require -rawin flag for raw message signing
    if $OPENSSL_BIN pkeyutl -sign -inkey "${private_key}" -rawin -in "$tmp_msg" -out "$tmp_sig" 2>/dev/null; then
        base64 < "$tmp_sig" | tr -d '\n'
    fi

    rm -f "$tmp_msg" "$tmp_sig"
}

# Verify a signature
verify_signature() {
    local message="$1"
    local signature="$2"
    local public_key_file="$3"

    # Use temporary files for verification (Ed25519 requires -rawin flag)
    local tmp_msg=$(mktemp)
    local tmp_sig=$(mktemp)

    echo -n "${message}" > "$tmp_msg"
    echo -n "${signature}" | base64 -d > "$tmp_sig"

    # Note: Ed25519 keys require -rawin flag for raw message verification
    local result=1
    if $OPENSSL_BIN pkeyutl -verify -pubin -inkey "${public_key_file}" -rawin -in "$tmp_msg" -sigfile "$tmp_sig" 2>/dev/null; then
        result=0
    fi

    rm -f "$tmp_msg" "$tmp_sig"
    return $result
}

# =============================================================================
# Address Parsing
# =============================================================================

# Parse AMP address: name@tenant.provider
# Sets: ADDR_NAME, ADDR_TENANT, ADDR_PROVIDER, ADDR_IS_LOCAL
parse_address() {
    local address="$1"

    # Reset
    ADDR_NAME=""
    ADDR_TENANT=""
    ADDR_PROVIDER=""
    ADDR_IS_LOCAL=false

    # Check if it's a full address (contains @)
    if [[ "$address" == *"@"* ]]; then
        ADDR_NAME="${address%%@*}"
        local domain="${address#*@}"

        # Check if domain has tenant.provider format
        if [[ "$domain" == *"."* ]]; then
            ADDR_TENANT="${domain%%.*}"
            ADDR_PROVIDER="${domain#*.}"
        else
            # Just provider, no tenant
            ADDR_TENANT="default"
            ADDR_PROVIDER="$domain"
        fi
    else
        # Short form - just a name, use the configured tenant
        ADDR_NAME="$address"
        # Try to get tenant from config, then from AI Maestro, then default
        if [ -n "${AMP_TENANT:-}" ]; then
            ADDR_TENANT="${AMP_TENANT}"
        else
            local org
            org=$(get_organization 2>/dev/null) || true
            ADDR_TENANT="${org:-default}"
        fi
        ADDR_PROVIDER="${AMP_PROVIDER_DOMAIN}"
    fi

    # Check if local (aimaestro.local or legacy "local" or "default.local")
    # This ensures backward compatibility with old address formats
    if [ "${ADDR_PROVIDER}" = "${AMP_PROVIDER_DOMAIN}" ] || \
       [ "${ADDR_PROVIDER}" = "aimaestro.local" ] || \
       [ "${ADDR_PROVIDER}" = "local" ] || \
       [[ "${ADDR_PROVIDER}" == *".local" ]]; then
        ADDR_IS_LOCAL=true
    fi
}

# Build full address from components
# Format: name@tenant.aimaestro.local
build_address() {
    local name="$1"
    local tenant="${2:-default}"
    local provider="${3:-${AMP_PROVIDER_DOMAIN}}"

    echo "${name}@${tenant}.${provider}"
}

# =============================================================================
# Message Creation
# =============================================================================

# Generate message ID
generate_message_id() {
    local timestamp=$(date +%s%N | cut -c1-13)
    local random=$(head -c 4 /dev/urandom | xxd -p)
    echo "msg_${timestamp}_${random}"
}

# Validate message ID format (security: prevent path traversal)
validate_message_id() {
    local id="$1"
    # Message IDs: msg_<timestamp>_<hex> or msg-<timestamp>-<alphanum>
    # Only allow alphanumeric, underscores, hyphens - no slashes, dots, etc.
    if [[ ! "$id" =~ ^msg[_-][0-9]+[_-][a-zA-Z0-9]+$ ]]; then
        echo "Error: Invalid message ID format: ${id}" >&2
        return 1
    fi
    return 0
}

# Create AMP message envelope
create_message() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local type="${4:-notification}"
    local priority="${5:-normal}"
    local in_reply_to="${6:-}"
    local context="${7:-null}"

    # Must be initialized
    if ! load_config; then
        echo "Error: AMP not initialized. Run 'amp-init' first." >&2
        return 1
    fi

    local id=$(generate_message_id)
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local thread_id="${in_reply_to:-$id}"

    # Parse destination address
    parse_address "$to"
    local full_to=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

    # Build message JSON
    local message_json
    message_json=$(jq -n \
        --arg id "$id" \
        --arg from "$AMP_ADDRESS" \
        --arg to "$full_to" \
        --arg subject "$subject" \
        --arg priority "$priority" \
        --arg timestamp "$timestamp" \
        --arg thread_id "$thread_id" \
        --arg in_reply_to "$in_reply_to" \
        --arg type "$type" \
        --arg body "$body" \
        --argjson context "$context" \
        '{
            envelope: {
                version: "amp/0.1",
                id: $id,
                from: $from,
                to: $to,
                subject: $subject,
                priority: $priority,
                timestamp: $timestamp,
                thread_id: $thread_id,
                in_reply_to: (if $in_reply_to == "" then null else $in_reply_to end),
                expires_at: null,
                signature: null
            },
            payload: {
                type: $type,
                message: $body,
                context: $context
            },
            metadata: {
                status: "unread",
                queued_at: $timestamp,
                delivery_attempts: 0
            }
        }')

    echo "$message_json"
}

# =============================================================================
# Message Storage (Local Provider)
# =============================================================================

# Sanitize address for use as directory name
sanitize_address_for_path() {
    local address="$1"
    # Replace @ and . with underscores, remove other special chars
    echo "$address" | sed 's/[@.]/_/g' | sed 's/[^a-zA-Z0-9_-]//g'
}

# Save message to inbox (organized by sender)
save_to_inbox() {
    local message_json="$1"
    local apply_security="${2:-true}"

    local id=$(echo "$message_json" | jq -r '.envelope.id')
    local from=$(echo "$message_json" | jq -r '.envelope.from')
    local sender_dir=$(sanitize_address_for_path "$from")

    # Create sender subdirectory
    local inbox_sender_dir="${AMP_INBOX_DIR}/${sender_dir}"
    mkdir -p "$inbox_sender_dir"

    # Apply content security if enabled and security module loaded
    if [ "$apply_security" = "true" ] && type apply_content_security &>/dev/null; then
        # Load local config for tenant
        load_config 2>/dev/null || true
        local local_tenant="${AMP_TENANT:-default}"

        # Check if signature is present (assume valid for local, need verification for external)
        local signature=$(echo "$message_json" | jq -r '.envelope.signature // empty')
        local sig_valid="false"

        # For local messages (same machine), trust them
        local from_provider=""
        if [[ "$from" == *"@"* ]]; then
            local domain="${from#*@}"
            if [[ "$domain" == *"."* ]]; then
                from_provider="${domain#*.}"
            fi
        fi

        if [ "$from_provider" = "local" ] || [ "$from_provider" = "$AMP_LOCAL_DOMAIN" ]; then
            sig_valid="true"
        elif [ -n "$signature" ]; then
            # For external messages, would need to verify signature
            # For now, mark as external if signature present
            sig_valid="true"
        fi

        # Apply security
        message_json=$(apply_content_security "$message_json" "$local_tenant" "$sig_valid")
    fi

    # Add received_at to local metadata
    message_json=$(echo "$message_json" | jq \
        --arg received "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.local = (.local // {}) + {received_at: $received, status: "unread"}')

    local inbox_file="${inbox_sender_dir}/${id}.json"
    echo "$message_json" > "$inbox_file"
    echo "$inbox_file"
}

# Save message to sent (organized by recipient)
save_to_sent() {
    local message_json="$1"

    local id=$(echo "$message_json" | jq -r '.envelope.id')
    local to=$(echo "$message_json" | jq -r '.envelope.to')
    local recipient_dir=$(sanitize_address_for_path "$to")

    # Create recipient subdirectory
    local sent_recipient_dir="${AMP_SENT_DIR}/${recipient_dir}"
    mkdir -p "$sent_recipient_dir"

    # Add sent_at to local metadata
    message_json=$(echo "$message_json" | jq \
        --arg sent "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.local = (.local // {}) + {sent_at: $sent}')

    local sent_file="${sent_recipient_dir}/${id}.json"
    echo "$message_json" > "$sent_file"
    echo "$sent_file"
}

# List inbox messages (handles nested sender directories)
list_inbox() {
    local status_filter="${1:-}"  # Optional: unread, read, all

    if [ ! -d "$AMP_INBOX_DIR" ]; then
        echo "[]"
        return 0
    fi

    # Collect all message files from all sender subdirectories
    local msg_files=()
    shopt -s nullglob

    # Check for old flat structure (backward compatibility)
    for msg_file in "${AMP_INBOX_DIR}"/*.json; do
        msg_files+=("$msg_file")
    done

    # Check nested sender directories (protocol-compliant structure)
    for sender_dir in "${AMP_INBOX_DIR}"/*/; do
        if [ -d "$sender_dir" ]; then
            for msg_file in "${sender_dir}"*.json; do
                msg_files+=("$msg_file")
            done
        fi
    done
    shopt -u nullglob

    if [ ${#msg_files[@]} -eq 0 ]; then
        echo "[]"
        return 0
    fi

    # Use jq slurp to read all files at once, then filter and sort
    # Check both .metadata.status (old) and .local.status (new)
    if [ -n "$status_filter" ] && [ "$status_filter" != "all" ]; then
        jq -s --arg status "$status_filter" \
            '[.[] | select(
                (.local.status // .metadata.status // "unread") == $status or
                ($status == "unread" and (.local.status // .metadata.status) == null)
            )] | sort_by(.envelope.timestamp) | reverse' \
            "${msg_files[@]}"
    else
        jq -s 'sort_by(.envelope.timestamp) | reverse' "${msg_files[@]}"
    fi
}

# Find message file by ID (searches flat and nested structures)
find_message_file() {
    local message_id="$1"
    local base_dir="$2"

    # Security: validate message ID format
    if ! validate_message_id "$message_id"; then
        return 1
    fi

    # Check flat structure first (backward compatibility)
    local flat_file="${base_dir}/${message_id}.json"
    if [ -f "$flat_file" ]; then
        echo "$flat_file"
        return 0
    fi

    # Search in subdirectories (protocol-compliant structure)
    shopt -s nullglob
    for subdir in "${base_dir}"/*/; do
        if [ -d "$subdir" ]; then
            local nested_file="${subdir}${message_id}.json"
            if [ -f "$nested_file" ]; then
                shopt -u nullglob
                echo "$nested_file"
                return 0
            fi
        fi
    done
    shopt -u nullglob

    return 1
}

# Read a specific message
read_message() {
    local message_id="$1"
    local box="${2:-inbox}"  # inbox or sent

    local msg_dir
    if [ "$box" = "inbox" ]; then
        msg_dir="$AMP_INBOX_DIR"
    else
        msg_dir="$AMP_SENT_DIR"
    fi

    local msg_file
    msg_file=$(find_message_file "$message_id" "$msg_dir")

    if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
        echo "Error: Message not found: ${message_id}" >&2
        return 1
    fi

    cat "$msg_file"
}

# Mark message as read
mark_as_read() {
    local message_id="$1"

    local msg_file
    msg_file=$(find_message_file "$message_id" "$AMP_INBOX_DIR")

    if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
        echo "Error: Message not found: ${message_id}" >&2
        return 1
    fi

    # Update both old (.metadata.status) and new (.local.status) locations
    local updated=$(jq '.metadata.status = "read" | .local.status = "read"' "$msg_file")
    echo "$updated" > "$msg_file"
}

# Delete a message
delete_message() {
    local message_id="$1"
    local box="${2:-inbox}"

    local msg_dir
    if [ "$box" = "inbox" ]; then
        msg_dir="$AMP_INBOX_DIR"
    else
        msg_dir="$AMP_SENT_DIR"
    fi

    local msg_file
    msg_file=$(find_message_file "$message_id" "$msg_dir")

    if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
        echo "Error: Message not found: ${message_id}" >&2
        return 1
    fi

    rm "$msg_file"
}

# =============================================================================
# Provider Routing
# =============================================================================

# Get registration for a provider
get_registration() {
    local provider="$1"
    local reg_file="${AMP_REGISTRATIONS_DIR}/${provider}.json"

    if [ -f "$reg_file" ]; then
        cat "$reg_file"
        return 0
    fi

    return 1
}

# Check if registered with a provider
is_registered() {
    local provider="$1"
    [ -f "${AMP_REGISTRATIONS_DIR}/${provider}.json" ]
}

# Route message to appropriate provider
# Returns: "local" or provider name
get_message_route() {
    local to_address="$1"

    parse_address "$to_address"

    if [ "$ADDR_IS_LOCAL" = true ]; then
        echo "local"
    else
        echo "$ADDR_PROVIDER"
    fi
}

# =============================================================================
# Display Helpers
# =============================================================================

# Format timestamp for display
format_timestamp() {
    local ts="$1"

    if command -v gdate &>/dev/null; then
        gdate -d "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts"
    elif date --version 2>&1 | grep -q GNU; then
        date -d "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts"
    else
        # macOS date
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts"
    fi
}

# Priority indicator
priority_indicator() {
    local priority="$1"

    case "$priority" in
        urgent) echo "🔴" ;;
        high)   echo "🟠" ;;
        normal) echo "🟢" ;;
        low)    echo "⚪" ;;
        *)      echo "🟢" ;;
    esac
}

# Status indicator
status_indicator() {
    local status="$1"

    case "$status" in
        unread)   echo "●" ;;
        read)     echo "○" ;;
        archived) echo "📦" ;;
        *)        echo "○" ;;
    esac
}

# =============================================================================
# Auto-detect Agent Name
# =============================================================================

# Try to detect agent name from environment
detect_agent_name() {
    # 1. Check CLAUDE_AGENT_NAME env var
    if [ -n "${CLAUDE_AGENT_NAME:-}" ]; then
        echo "$CLAUDE_AGENT_NAME"
        return 0
    fi

    # 2. Check tmux session name
    if [ -n "${TMUX:-}" ]; then
        local tmux_session
        tmux_session=$(tmux display-message -p '#S' 2>/dev/null)
        if [ -n "$tmux_session" ]; then
            # Remove any _N suffix (multi-session pattern)
            echo "${tmux_session%_[0-9]*}"
            return 0
        fi
    fi

    # 3. Check git repo name
    if command -v git &>/dev/null; then
        local repo_name
        repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
        if [ -n "$repo_name" ]; then
            echo "$repo_name"
            return 0
        fi
    fi

    # 4. Fallback to hostname + user
    echo "$(whoami)-$(hostname -s | tr '[:upper:]' '[:lower:]')"
}

# =============================================================================
# Initialization Check
# =============================================================================

require_init() {
    if ! is_initialized; then
        # Auto-initialize: generate keys, save config, register
        local _agent_name=""
        if [ -n "${CLAUDE_AGENT_NAME:-}" ]; then
            _agent_name="${CLAUDE_AGENT_NAME}"
        elif [ -n "${TMUX:-}" ]; then
            _agent_name=$(tmux display-message -p '#S' 2>/dev/null || true)
            _agent_name="${_agent_name%_[0-9]*}"
        fi

        if [ -z "$_agent_name" ]; then
            echo "Error: Cannot determine agent name for auto-init." >&2
            echo "Set CLAUDE_AGENT_NAME or run inside a tmux session." >&2
            exit 1
        fi

        echo "  Auto-initializing AMP identity for ${_agent_name}..." >&2

        # Get organization
        local _tenant
        _tenant=$(get_organization 2>/dev/null) || true
        [ -z "$_tenant" ] && _tenant="default"

        # Generate keypair
        local _fingerprint
        _fingerprint=$(generate_keypair)

        # Save config
        save_config "$_agent_name" "$_tenant" "$_fingerprint" >/dev/null

        # Create identity file
        local _address="${_agent_name}@${_tenant}.${AMP_PROVIDER_DOMAIN}"
        create_identity_file "$_agent_name" "$_tenant" "$_address" "$_fingerprint" >/dev/null 2>&1 || true

        # Auto-register with AMP provider
        local _pub_key=""
        [ -f "${AMP_KEYS_DIR}/public.pem" ] && _pub_key=$(cat "${AMP_KEYS_DIR}/public.pem")

        if [ -n "$_pub_key" ]; then
            local _reg_req
            _reg_req=$(jq -n \
                --arg name "$_agent_name" \
                --arg tenant "$_tenant" \
                --arg publicKey "$_pub_key" \
                '{ name: $name, tenant: $tenant, public_key: $publicKey, key_algorithm: "Ed25519" }')

            local _reg_resp
            _reg_resp=$(curl -s -w "\n%{http_code}" --connect-timeout 3 -X POST \
                "${AMP_MAESTRO_URL}/api/v1/register" \
                -H "Content-Type: application/json" \
                -d "$_reg_req" 2>&1) || true

            local _reg_http
            _reg_http=$(echo "$_reg_resp" | tail -n1)
            local _reg_body
            _reg_body=$(echo "$_reg_resp" | sed '$d')

            if [ "$_reg_http" = "200" ] || [ "$_reg_http" = "201" ]; then
                local _api_key
                _api_key=$(echo "$_reg_body" | jq -r '.api_key // empty')
                if [ -n "$_api_key" ]; then
                    local _prov_name
                    _prov_name=$(echo "$_reg_body" | jq -r '.provider.name // "aimaestro.local"')
                    local _prov_endpoint
                    _prov_endpoint=$(echo "$_reg_body" | jq -r '.provider.endpoint // empty')
                    local _reg_address
                    _reg_address=$(echo "$_reg_body" | jq -r '.address // empty')
                    local _reg_agent_id
                    _reg_agent_id=$(echo "$_reg_body" | jq -r '.agent_id // empty')

                    jq -n \
                        --arg provider "$_prov_name" \
                        --arg apiUrl "${_prov_endpoint:-${AMP_MAESTRO_URL}/api/v1}" \
                        --arg agentName "$_agent_name" \
                        --arg tenant "$_tenant" \
                        --arg address "${_reg_address:-$_address}" \
                        --arg apiKey "$_api_key" \
                        --arg providerAgentId "$_reg_agent_id" \
                        --arg fingerprint "$_fingerprint" \
                        --arg registeredAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                        '{
                            provider: $provider, apiUrl: $apiUrl, agentName: $agentName,
                            tenant: $tenant, address: $address, apiKey: $apiKey,
                            providerAgentId: $providerAgentId, fingerprint: $fingerprint,
                            registeredAt: $registeredAt
                        }' > "${AMP_REGISTRATIONS_DIR}/${_prov_name}.json"
                    chmod 600 "${AMP_REGISTRATIONS_DIR}/${_prov_name}.json"
                    echo "  ✅ AMP identity registered for ${_agent_name}" >&2
                fi
            fi
        fi
    fi

    load_config
}
