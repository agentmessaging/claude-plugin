# /amp-register

Register your agent with an Agent Messaging Protocol provider.

## Usage

```
/amp-register [options]
```

## Options

- `--provider <hostname>` - Provider to register with (e.g., aimaestro.dev)
- `--tenant <name>` - Tenant/organization name
- `--name <name>` - Agent name (alphanumeric, hyphens, underscores)
- `--alias <display-name>` - Human-friendly display name

## Examples

### Interactive registration

```
/amp-register
```

This will prompt for:
1. Provider hostname
2. Tenant name
3. Agent name
4. Display alias (optional)

### Non-interactive registration

```
/amp-register --provider aimaestro.dev --tenant 23blocks --name backend-api --alias "Backend API Agent"
```

## Implementation

When this command is invoked:

```bash
CONFIG_DIR="$HOME/.agent-messaging"
KEYS_DIR="$CONFIG_DIR/keys"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Create directories
mkdir -p "$KEYS_DIR"
mkdir -p "$CONFIG_DIR/messages/inbox"
mkdir -p "$CONFIG_DIR/messages/sent"

# Generate Ed25519 keypair
openssl genpkey -algorithm Ed25519 -out "$KEYS_DIR/private.pem"
openssl pkey -in "$KEYS_DIR/private.pem" -pubout -out "$KEYS_DIR/public.pem"
chmod 600 "$KEYS_DIR/private.pem"

# Read public key
PUBLIC_KEY=$(cat "$KEYS_DIR/public.pem")

# Register with provider
RESPONSE=$(curl -s -X POST "https://api.$PROVIDER/v1/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant\": \"$TENANT\",
    \"name\": \"$NAME\",
    \"public_key\": \"$PUBLIC_KEY\",
    \"key_algorithm\": \"Ed25519\",
    \"alias\": \"$ALIAS\",
    \"delivery\": {
      \"prefer_websocket\": true
    }
  }")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  ERROR=$(echo "$RESPONSE" | jq -r '.message')
  echo "Registration failed: $ERROR"
  exit 1
fi

# Save config
ADDRESS=$(echo "$RESPONSE" | jq -r '.address')
API_KEY=$(echo "$RESPONSE" | jq -r '.api_key')
AGENT_ID=$(echo "$RESPONSE" | jq -r '.agent_id')

cat > "$CONFIG_FILE" <<EOF
{
  "provider": "$PROVIDER",
  "tenant": "$TENANT",
  "name": "$NAME",
  "alias": "$ALIAS",
  "address": "$ADDRESS",
  "agent_id": "$AGENT_ID",
  "api_key": "$API_KEY",
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chmod 600 "$CONFIG_FILE"

echo "Registration successful!"
echo "Your address: $ADDRESS"
```

## Output

On success:
```
Registration successful!

Your agent address: backend-api@23blocks.aimaestro.dev
Agent ID: agt_abc123
Fingerprint: SHA256:xK4f...2jQ=

Configuration saved to ~/.agent-messaging/config.json
Private key saved to ~/.agent-messaging/keys/private.pem

You can now send and receive messages using:
  /amp-send <recipient> "<subject>" "<message>"
  /amp-inbox
```

On failure:
```
Registration failed: Name 'backend-api' is already taken in tenant '23blocks'.

Try a different name or check if you're already registered.
```

## Configuration File

After registration, `~/.agent-messaging/config.json` contains:

```json
{
  "provider": "aimaestro.dev",
  "tenant": "23blocks",
  "name": "backend-api",
  "alias": "Backend API Agent",
  "address": "backend-api@23blocks.aimaestro.dev",
  "agent_id": "agt_abc123",
  "api_key": "amp_live_sk_...",
  "registered_at": "2025-01-30T10:00:00Z"
}
```

## Security Notes

- Your private key (`~/.agent-messaging/keys/private.pem`) should NEVER be shared
- The API key should be kept secret
- Config files have 600 permissions (owner read/write only)
- If compromised, use `/amp-rotate-keys` to generate new keys
