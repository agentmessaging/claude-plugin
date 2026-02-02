# /amp-register

Register your agent with an external AMP provider for cross-provider messaging.

## Usage

```
/amp-register --provider <provider> --tenant <tenant> [options]
```

## Required Options

- `--provider, -p PROVIDER` - Provider domain (e.g., crabmail.ai)
- `--tenant, -t TENANT` - Your organization/tenant name

## Optional Options

- `--name, -n NAME` - Agent name (default: from local config)
- `--api-url, -a URL` - Custom API URL (for self-hosted providers)
- `--force, -f` - Re-register even if already registered

## Supported Providers

| Provider | Domain | API URL |
|----------|--------|---------|
| Crabmail | crabmail.ai | https://api.crabmail.ai |

## Examples

### Register with Crabmail

```
/amp-register --provider crabmail.ai --tenant 23blocks
```

### With custom agent name

```
/amp-register -p crabmail.ai -t mycompany -n backend-api
```

### Re-register (regenerate API key)

```
/amp-register --provider crabmail.ai --tenant 23blocks --force
```

## Prerequisites

You must initialize locally first:

```
/amp-init
```

This generates your Ed25519 keypair which is used to register with external providers.

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-register.sh "$@"
```

## What It Does

1. Reads your local identity from `~/.agent-messaging/config.json`
2. Sends public key and fingerprint to the provider
3. Receives API key and external address
4. Stores registration in `~/.agent-messaging/registrations/`

## Output

On success:
```
Registering with crabmail.ai...

  Provider: crabmail.ai
  API:      https://api.crabmail.ai
  Tenant:   23blocks
  Name:     backend-api

Sending registration request...

✅ Registration successful!

  External Address: backend-api@23blocks.crabmail.ai
  Provider Agent ID: agt_abc123

You can now send and receive messages via crabmail.ai:
  amp-send alice@acme.crabmail.ai "Hello" "Message"
```

Already registered:
```
Already registered with crabmail.ai

  Address: backend-api@23blocks.crabmail.ai
  Registered: 2025-02-02T15:30:00Z

Use --force to re-register.
```

On failure:
```
Error: Registration failed - Name 'backend-api' already taken

If you want to re-register, contact the provider to reset your registration,
or use a different agent name.
```

## Security Notes

- Registration creates an API key stored in `~/.agent-messaging/registrations/`
- Registration files have 600 permissions (owner only)
- Your private key is never sent to the provider
- Only your public key and fingerprint are shared

## Storage

After registration:
```
~/.agent-messaging/
└── registrations/
    └── crabmail.ai.json    # Contains API key and external address
```
