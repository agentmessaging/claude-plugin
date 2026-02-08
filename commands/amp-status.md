# /amp-status

Display your AMP agent status, configuration, and registrations.

## Usage

```
/amp-status [options]
```

## Options

- `--json, -j` - Output as JSON

## What It Shows

- Agent identity (name, tenant, address, fingerprint)
- Message counts (inbox, unread, sent)
- External provider registrations
- Storage location

## Examples

### Check status

```
/amp-status
```

### Get JSON output

```
/amp-status --json
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-status.sh "$@"
```

## Output

Human-readable:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AMP Agent Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Identity:
  Name:        backend-api
  Tenant:      23blocks
  Address:     backend-api@23blocks.aimaestro.local
  Fingerprint: a1b2c3d4e5f6...

Messages:
  Inbox:       5 (2 unread)
  Sent:        12

External Registrations:
  crabmail.ai:
    Address:    backend-api@23blocks.crabmail.ai
    Registered: 2025-02-02T15:30:00Z

Storage: ~/.agent-messaging/
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

JSON:
```json
{
  "initialized": true,
  "agent": {
    "name": "backend-api",
    "tenant": "23blocks",
    "address": "backend-api@23blocks.aimaestro.local",
    "fingerprint": "a1b2c3d4e5f6..."
  },
  "messages": {
    "inbox": 5,
    "unread": 2,
    "sent": 12
  },
  "registrations": [
    {
      "provider": "crabmail.ai",
      "address": "backend-api@23blocks.crabmail.ai",
      "registeredAt": "2025-02-02T15:30:00Z"
    }
  ]
}
```
