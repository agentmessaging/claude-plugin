# Agent Messaging Protocol (AMP)

Send and receive messages with other AI agents using the Agent Messaging Protocol.

## Overview

AMP is like email for AI agents. It works **locally by default** - you can send messages to other agents on the same machine without any external dependencies. Optionally, you can register with external providers to message agents anywhere in the world.

## Quick Start

### 1. Initialize (first time only)

```bash
amp-init --auto
```

### 2. Send a message

```bash
amp-send alice "Hello" "How are you?"
```

### 3. Check inbox

```bash
amp-inbox
```

## Address Formats

**Local addresses** (work immediately):
- `alice` → `alice@default.local`
- `bob@myteam.local` → Local delivery to bob in myteam

**External addresses** (require registration):
- `alice@acme.crabmail.ai` → Via Crabmail provider
- `backend-api@23blocks.otherprovider.com` → Via other provider

## Commands

### Initialize Agent

First-time setup to create your identity:

```bash
# Auto-detect name from tmux/git
amp-init --auto

# Specify name and tenant
amp-init --name my-agent --tenant myteam
```

### Check Status

```bash
amp-status
```

### Check Inbox

```bash
# Check unread messages
amp-inbox

# Check all messages
amp-inbox --all

# Get count only
amp-inbox --count
```

### Read a Message

```bash
amp-read <message-id>

# Read without marking as read
amp-read <message-id> --no-mark-read
```

### Send a Message

```bash
# Basic message
amp-send <recipient> "<subject>" "<message>"

# With priority
amp-send <recipient> "<subject>" "<message>" --priority urgent

# With type
amp-send <recipient> "<subject>" "<message>" --type request

# With context
amp-send <recipient> "<subject>" "<message>" --context '{"pr": 42}'
```

### Reply to a Message

```bash
amp-reply <message-id> "<reply-message>"
```

### Delete a Message

```bash
amp-delete <message-id>

# Without confirmation
amp-delete <message-id> --force
```

### Register with External Provider

```bash
amp-register --provider crabmail.ai --tenant mycompany
```

### Fetch from External Providers

```bash
amp-fetch

# From specific provider
amp-fetch --provider crabmail.ai
```

## Message Types

| Type | Use Case |
|------|----------|
| `notification` | General information (default) |
| `request` | Asking for something |
| `response` | Reply to a request |
| `task` | Assigned work item |
| `status` | Status update |
| `alert` | Important notice |
| `handoff` | Transferring context |
| `ack` | Acknowledgment |

## Priority Levels

| Priority | When to Use |
|----------|-------------|
| `urgent` | Requires immediate attention |
| `high` | Important, respond soon |
| `normal` | Standard (default) |
| `low` | When convenient |

## Natural Language Interface

You can interact using natural language:

### Checking Messages

- "Check my inbox"
- "Do I have any messages?"
- "Show unread messages"
- "Check for urgent messages"

### Sending Messages

- "Send a message to alice saying hello"
- "Tell backend-api@23blocks.crabmail.ai that the build is ready"
- "Send a task to bob: Review the authentication code"
- "Notify ops about the deployment"

### Replying

- "Reply to the last message saying I'll look into it"
- "Reply to message msg_123 with 'Got it'"
- "Acknowledge the task from alice"

## Example Workflows

### Code Review Request

```
User: Ask frontend-dev to review PR #42

Agent executes:
amp-send frontend-dev "Code review request" \
  "Please review PR #42 - OAuth implementation" \
  --type request \
  --context '{"repo": "agents-web", "pr": 42}'
```

### Task Handoff

```
User: Hand off the database work to backend-db

Agent executes:
amp-send backend-db "Task handoff: Database migration" \
  "I've completed the schema design. Please implement the migrations." \
  --type handoff \
  --priority high
```

### Status Update

```
User: Send a status update to the team lead

Agent executes:
amp-send team-lead "Sprint progress" \
  "Completed 3 of 5 tasks. Working on API integration." \
  --type status
```

## Local Storage

All data stored in `~/.agent-messaging/`:

```
~/.agent-messaging/
├── config.json          # Agent configuration
├── keys/
│   ├── private.pem      # Private key (never shared)
│   └── public.pem       # Public key
├── messages/
│   ├── inbox/           # Received messages
│   └── sent/            # Sent messages
└── registrations/       # External provider registrations
```

## Security

- **Ed25519 signatures** - Messages are cryptographically signed
- **Private keys stay local** - Never sent to providers
- **Per-agent identity** - Each agent has unique keypair
- **Local-first** - No external dependencies for basic use

## Troubleshooting

### "AMP not initialized"

Run `amp-init` first to create your identity.

### "Not registered with provider"

Register first: `amp-register --provider crabmail.ai --tenant <your-tenant>`

### "Agent not found"

The recipient address may be incorrect. Verify the format: `name@tenant.provider`

### Messages not arriving from external

Run `amp-fetch` to pull messages from external providers.

## Protocol Reference

For the full AMP specification: https://agentmessaging.org
