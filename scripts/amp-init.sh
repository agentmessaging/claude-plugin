#!/bin/bash
# =============================================================================
# AMP Init - Initialize Agent Identity
# =============================================================================
#
# Sets up the agent's identity and cryptographic keys.
#
# Usage:
#   amp-init                     # Interactive mode
#   amp-init --auto              # Auto-detect name from environment
#   amp-init --name myagent      # Specify name directly
#   amp-init --name myagent --tenant mycompany
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
NAME=""
TENANT=""
AUTO_DETECT=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --name|-n)
            NAME="$2"
            shift 2
            ;;
        --tenant|-t)
            TENANT="$2"
            shift 2
            ;;
        --auto|-a)
            AUTO_DETECT=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: amp-init [options]"
            echo ""
            echo "Initialize your agent identity for the Agent Messaging Protocol."
            echo ""
            echo "Options:"
            echo "  --name, -n NAME      Agent name (e.g., backend-api)"
            echo "  --tenant, -t TENANT  Organization/tenant (auto-fetched from AI Maestro)"
            echo "  --auto, -a           Auto-detect name from environment"
            echo "  --force, -f          Overwrite existing configuration"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  amp-init --auto                    # Auto-detect from tmux/git"
            echo "  amp-init --name backend-api       # Set specific name"
            echo "  amp-init -n myagent               # Tenant auto-fetched from AI Maestro"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'amp-init --help' for usage."
            exit 1
            ;;
    esac
done

# Get organization from AI Maestro if not explicitly provided
if [ -z "$TENANT" ]; then
    echo "Fetching organization from AI Maestro..."
    ORG=$(get_organization 2>/dev/null) || true

    if [ -n "$ORG" ]; then
        TENANT="$ORG"
        echo "  Organization: ${TENANT}"
    else
        echo ""
        echo "⚠️  Organization not configured in AI Maestro."
        echo ""
        echo "Before using AMP, you must configure your organization:"
        echo "  1. Open AI Maestro at ${AMP_MAESTRO_URL:-http://localhost:23000}"
        echo "  2. Complete the organization setup"
        echo ""
        echo "Or specify a tenant manually with: amp-init --tenant myorg"
        echo ""
        exit 1
    fi
fi

# Check if already initialized
if is_initialized && [ "$FORCE" != true ]; then
    load_config
    echo "AMP is already initialized."
    echo ""
    echo "  Agent: ${AMP_AGENT_NAME}"
    echo "  Address: ${AMP_ADDRESS}"
    echo "  Fingerprint: ${AMP_FINGERPRINT}"
    echo ""
    echo "Use --force to reinitialize (will generate new keys)."
    exit 0
fi

# Get name
if [ -z "$NAME" ]; then
    if [ "$AUTO_DETECT" = true ]; then
        NAME=$(detect_agent_name)
        echo "Auto-detected agent name: ${NAME}"
    else
        # Interactive mode
        echo "Agent Messaging Protocol - Setup"
        echo "================================"
        echo ""

        # Suggest a name
        SUGGESTED=$(detect_agent_name)
        echo "Enter your agent name (or press Enter for '${SUGGESTED}'):"
        read -r NAME
        if [ -z "$NAME" ]; then
            NAME="$SUGGESTED"
        fi
    fi
fi

# Validate name
if [[ ! "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "Error: Invalid agent name '${NAME}'"
    echo "Name must start with alphanumeric and contain only letters, numbers, dots, underscores, and hyphens."
    exit 1
fi

# Normalize name to lowercase
NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')

echo ""
echo "Initializing AMP identity..."

# Ensure directories exist
ensure_amp_dirs

# Generate keypair
echo "  Generating Ed25519 keypair..."
FINGERPRINT=$(generate_keypair)

# Save configuration
echo "  Saving configuration..."
ADDRESS=$(save_config "$NAME" "$TENANT" "$FINGERPRINT")

echo ""
echo "✅ AMP initialized successfully!"
echo ""
echo "  Agent Name:  ${NAME}"
echo "  Tenant:      ${TENANT}"
echo "  Address:     ${ADDRESS}"
echo "  Fingerprint: ${FINGERPRINT}"
echo ""
echo "Your keys are stored in: ${AMP_KEYS_DIR}"
echo ""
echo "Next steps:"
echo "  - Send a message:    amp-send <recipient> \"Subject\" \"Message\""
echo "  - Check inbox:       amp-inbox"
echo "  - Register with provider: amp-register --provider crabmail.ai"
