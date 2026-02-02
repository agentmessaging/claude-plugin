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

# Configuration
AMP_DIR="${AMP_DIR:-${HOME}/.agent-messaging}"
AMP_CONFIG="${AMP_DIR}/config.json"
AMP_KEYS_DIR="${AMP_DIR}/keys"
AMP_MESSAGES_DIR="${AMP_DIR}/messages"
AMP_REGISTRATIONS_DIR="${AMP_DIR}/registrations"

# Default local provider
AMP_LOCAL_DOMAIN="local"

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

    local address="${name}@${tenant}.${AMP_LOCAL_DOMAIN}"

    jq -n \
        --arg name "$name" \
        --arg tenant "$tenant" \
        --arg address "$address" \
        --arg fingerprint "$fingerprint" \
        --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            version: "1.0",
            agent: {
                name: $name,
                tenant: $tenant,
                address: $address,
                fingerprint: $fingerprint,
                createdAt: $created
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
    openssl genpkey -algorithm Ed25519 -out "${private_key}" 2>/dev/null
    chmod 600 "${private_key}"

    # Extract public key
    openssl pkey -in "${private_key}" -pubout -out "${public_key}" 2>/dev/null
    chmod 644 "${public_key}"

    # Calculate fingerprint
    local fingerprint
    fingerprint=$(openssl pkey -in "${private_key}" -pubout -outform DER 2>/dev/null | \
                  openssl dgst -sha256 -binary | base64)

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
    openssl pkey -pubin -in "${public_key}" -outform DER 2>/dev/null | \
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

    echo -n "${message}" | openssl pkeyutl -sign -inkey "${private_key}" 2>/dev/null | base64 | tr -d '\n'
}

# Verify a signature
verify_signature() {
    local message="$1"
    local signature="$2"
    local public_key_file="$3"

    echo -n "${signature}" | base64 -d | \
        openssl pkeyutl -verify -pubin -inkey "${public_key_file}" -sigfile /dev/stdin \
        <<< "${message}" 2>/dev/null
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
        # Short form - just a name, use defaults
        ADDR_NAME="$address"
        ADDR_TENANT="${AMP_TENANT:-default}"
        ADDR_PROVIDER="${AMP_LOCAL_DOMAIN}"
    fi

    # Check if local
    if [ "${ADDR_PROVIDER}" = "${AMP_LOCAL_DOMAIN}" ] || [ "${ADDR_PROVIDER}" = "aimaestro.local" ]; then
        ADDR_IS_LOCAL=true
    fi
}

# Build full address from components
build_address() {
    local name="$1"
    local tenant="${2:-default}"
    local provider="${3:-${AMP_LOCAL_DOMAIN}}"

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

# Save message to inbox
save_to_inbox() {
    local message_json="$1"

    local id=$(echo "$message_json" | jq -r '.envelope.id')
    local inbox_file="${AMP_MESSAGES_DIR}/inbox/${id}.json"

    echo "$message_json" > "$inbox_file"
    echo "$inbox_file"
}

# Save message to sent
save_to_sent() {
    local message_json="$1"

    local id=$(echo "$message_json" | jq -r '.envelope.id')
    local sent_file="${AMP_MESSAGES_DIR}/sent/${id}.json"

    echo "$message_json" > "$sent_file"
    echo "$sent_file"
}

# List inbox messages
list_inbox() {
    local status_filter="${1:-}"  # Optional: unread, read, all

    local inbox_dir="${AMP_MESSAGES_DIR}/inbox"

    if [ ! -d "$inbox_dir" ] || [ -z "$(ls -A "$inbox_dir" 2>/dev/null)" ]; then
        echo "[]"
        return 0
    fi

    local messages="[]"

    for msg_file in "${inbox_dir}"/*.json; do
        [ -f "$msg_file" ] || continue

        local msg_status=$(jq -r '.metadata.status // "unread"' "$msg_file" 2>/dev/null)

        # Apply filter
        if [ -n "$status_filter" ] && [ "$status_filter" != "all" ]; then
            if [ "$msg_status" != "$status_filter" ]; then
                continue
            fi
        fi

        # Add to array
        messages=$(echo "$messages" | jq --slurpfile msg "$msg_file" '. + $msg')
    done

    # Sort by timestamp (newest first)
    echo "$messages" | jq 'sort_by(.envelope.timestamp) | reverse'
}

# Read a specific message
read_message() {
    local message_id="$1"
    local box="${2:-inbox}"  # inbox or sent

    local msg_file="${AMP_MESSAGES_DIR}/${box}/${message_id}.json"

    if [ ! -f "$msg_file" ]; then
        echo "Error: Message not found: ${message_id}" >&2
        return 1
    fi

    cat "$msg_file"
}

# Mark message as read
mark_as_read() {
    local message_id="$1"

    local msg_file="${AMP_MESSAGES_DIR}/inbox/${message_id}.json"

    if [ ! -f "$msg_file" ]; then
        echo "Error: Message not found: ${message_id}" >&2
        return 1
    fi

    local updated=$(jq '.metadata.status = "read"' "$msg_file")
    echo "$updated" > "$msg_file"
}

# Delete a message
delete_message() {
    local message_id="$1"
    local box="${2:-inbox}"

    local msg_file="${AMP_MESSAGES_DIR}/${box}/${message_id}.json"

    if [ ! -f "$msg_file" ]; then
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
        echo "Error: AMP not initialized." >&2
        echo "" >&2
        echo "Run 'amp-init' to set up your agent identity." >&2
        echo "Or run 'amp-init --auto' to auto-detect your agent name." >&2
        exit 1
    fi

    load_config
}
