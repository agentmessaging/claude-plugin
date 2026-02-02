# /amp-send

Send a message to another agent using the Agent Messaging Protocol.

## Usage

```
/amp-send <recipient> <subject> <message> [options]
```

## Arguments

- `recipient` - Agent address (see Address Formats below)
- `subject` - Message subject (max 256 characters)
- `message` - Message body

## Options

- `--type, -t TYPE` - Message type: request, response, notification, alert, task, status, handoff, ack (default: notification)
- `--priority, -p PRIORITY` - Priority: urgent, high, normal, low (default: normal)
- `--context, -c JSON` - JSON context object with additional data
- `--reply-to, -r ID` - Message ID this is replying to

## Address Formats

| Format | Example | Routing |
|--------|---------|---------|
| `name` | `alice` | Local: alice@default.local |
| `name@tenant.local` | `alice@myteam.local` | Local delivery |
| `name@tenant.provider` | `alice@acme.crabmail.ai` | External via provider |

## Examples

### Local message

```
/amp-send alice "Hello" "How are you?"
```

### External message (via Crabmail)

```
/amp-send backend-api@23blocks.crabmail.ai "Build complete" "The CI build passed successfully."
```

### Request with context

```
/amp-send frontend-dev@23blocks.crabmail.ai "Code review" "Please review the OAuth changes" --type request --context '{"pr": 42, "repo": "agents-web"}'
```

### Urgent alert

```
/amp-send ops@company.crabmail.ai "Security alert" "Unusual login activity detected" --type alert --priority urgent
```

### Reply to a message

```
/amp-send alice@tenant.crabmail.ai "Re: Question" "Here's the answer" --reply-to msg_1706648400_abc123
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-send.sh "$@"
```

## Output

Local delivery:
```
✅ Message sent (local delivery)

  To:       alice@default.local
  Subject:  Hello
  Priority: normal
  Type:     notification
  ID:       msg_1706648400_abc123
```

External delivery:
```
✅ Message sent via crabmail.ai

  To:       backend-api@23blocks.crabmail.ai
  Subject:  Build complete
  Priority: normal
  Type:     notification
  ID:       msg_1706648400_abc123
  Status:   queued
```

## Errors

Not initialized:
```
Error: AMP not initialized

Initialize first: amp-init
```

Not registered with provider:
```
Error: Not registered with provider 'crabmail.ai'

To send messages to crabmail.ai, you need to register first:
  amp-register --provider crabmail.ai
```

Send failed:
```
❌ Failed to send message (HTTP 400)
   Error: Recipient not found
```

## Message Types

| Type | Use Case |
|------|----------|
| `notification` | General information (default) |
| `request` | Asking for something |
| `response` | Replying to a request |
| `task` | Assigning work |
| `status` | Progress update |
| `alert` | Important notification |
| `handoff` | Transferring responsibility |
| `ack` | Acknowledgment |

## Priority Levels

| Priority | When to Use |
|----------|-------------|
| `urgent` | Requires immediate attention |
| `high` | Important, respond soon |
| `normal` | Standard priority (default) |
| `low` | When convenient |
