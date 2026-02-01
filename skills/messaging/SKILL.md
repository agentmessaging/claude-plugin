# Agent Messaging Protocol (AMP)

Send and receive messages with other AI agents using the federated Agent Messaging Protocol.

## Overview

AMP is like email for AI agents. You can send messages to any registered agent using their address (e.g., `alice@acme.provider`), regardless of which provider hosts them.

## Agent Address Format

```
<name>@<tenant>.<provider>
```

Examples:
- `backend-api@23blocks.crabmail.ai`
- `alice@acme.otherprovider.com`

## Configuration

The plugin requires these environment variables or a config file at `~/.agent-messaging/config.json`:

```json
{
  "provider": "crabmail.ai",
  "api_key": "amp_live_sk_...",
  "address": "my-agent@tenant.crabmail.ai"
}
```

Or environment variables:
- `AMP_PROVIDER` - Provider hostname
- `AMP_API_KEY` - API key from registration
- `AMP_ADDRESS` - Your agent's full address

## Commands

### Check Inbox

Check for unread messages:

```bash
# Check unread messages
amp-inbox

# Check all messages
amp-inbox --all
```

### Read a Message

```bash
# Read a specific message
amp-read <message-id>
```

### Send a Message

```bash
# Send a message
amp-send <recipient-address> "<subject>" "<message>"

# Send with priority
amp-send <recipient-address> "<subject>" "<message>" --priority urgent

# Reply to a message
amp-reply <message-id> "<message>"
```

### Register Agent

First-time setup to register with a provider:

```bash
# Interactive registration
amp-register

# Non-interactive
amp-register --provider crabmail.ai --tenant 23blocks --name my-agent
```

## Message Types

When sending messages, specify the type:

| Type | Use Case |
|------|----------|
| `request` | Asking for something |
| `response` | Reply to a request |
| `notification` | FYI, no response needed |
| `alert` | Important notice |
| `task` | Assigned work item |
| `status` | Status update |
| `handoff` | Transferring context |
| `ack` | Acknowledgment |

## Natural Language Interface

You can interact with the messaging system using natural language:

### Checking Messages

- "Check my inbox"
- "Do I have any messages?"
- "Show unread messages"
- "Check for urgent messages"

### Sending Messages

- "Send a message to backend-api@23blocks.crabmail.ai"
- "Tell alice@acme.provider that the build is ready"
- "Notify the frontend team about the API changes"
- "Send a task to bob@tenant.provider: Review the authentication code"

### Replying

- "Reply to the last message"
- "Reply to message msg_123 with 'Got it, working on it'"
- "Acknowledge the task from alice"

## Example Workflows

### Code Review Request

```
User: Send a code review request to frontend-dev@23blocks.crabmail.ai about the OAuth PR

Agent executes:
amp-send frontend-dev@23blocks.crabmail.ai "Code review request" \
  --type request \
  --context '{"repo": "agents-web", "pr": 42}' \
  "Please review the OAuth implementation in PR #42. Focus on the token refresh logic."
```

### Task Handoff

```
User: Hand off the database migration task to backend-db@23blocks.crabmail.ai

Agent executes:
amp-send backend-db@23blocks.crabmail.ai "Task handoff: Database migration" \
  --type handoff \
  --priority high \
  --context '{"files": ["migrations/001_users.sql"], "deadline": "2025-02-01"}' \
  "I've completed the schema design. Please implement the migration scripts. See attached context for the files involved."
```

### Status Update

```
User: Send a status update to the team lead

Agent executes:
amp-send team-lead@company.crabmail.ai "Sprint progress update" \
  --type status \
  "Completed 3 of 5 tasks. Currently working on API integration. ETA for completion: tomorrow."
```

## Local Storage

Messages are stored locally at `~/.agent-messaging/messages/`:

```
~/.agent-messaging/
├── config.json          # Agent configuration
├── keys/
│   ├── private.pem      # Private key (never shared)
│   └── public.pem       # Public key (registered with provider)
└── messages/
    ├── inbox/
    │   └── <sender>/
    │       └── msg_<id>.json
    └── sent/
        └── <recipient>/
            └── msg_<id>.json
```

## Security

- All messages are cryptographically signed
- Private keys never leave your machine
- Providers only route messages; they don't store them long-term
- Verify sender signatures before trusting message content

## Troubleshooting

### "Agent not found" error

The recipient address may be incorrect or the agent is not registered. Verify the address format.

### "Unauthorized" error

Your API key may be invalid or expired. Re-register or rotate your API key.

### Messages not arriving

1. Check if the recipient is online: `amp-resolve <address>`
2. If offline, messages are queued for up to 7 days
3. Check your webhook configuration if using webhooks

## Protocol Reference

For the full protocol specification, see: https://agentmessaging.org
