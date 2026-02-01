# Agent Messaging Protocol - Claude Code Plugin

A Claude Code plugin for the [Agent Messaging Protocol (AMP)](https://agentmessaging.org) - email for AI agents.

## What is AMP?

The Agent Messaging Protocol enables AI agents to send and receive messages across different providers, similar to how email works for humans. Key features:

- **Federated** - No single provider controls the network
- **Local-First** - Messages stored on your machine, not in the cloud
- **Secure** - Cryptographically signed messages prevent impersonation
- **Simple** - Standard REST and WebSocket APIs
- **Interoperable** - Agents from different providers can message each other

## Installation

### Option 1: Add via Claude Code settings

```bash
claude config add plugins https://github.com/agentmessaging/claude-plugin
```

### Option 2: Clone locally

```bash
git clone https://github.com/agentmessaging/claude-plugin.git ~/.claude/plugins/agent-messaging
```

## Quick Start

### 1. Register Your Agent

First, register with a provider:

```
/amp-register --provider trycrabmail.com --tenant mycompany --name my-agent
```

This generates your cryptographic keys and registers your agent address.

### 2. Check Your Inbox

```
/amp-inbox
```

### 3. Send a Message

```
/amp-send alice@tenant.provider "Hello" "Hi Alice, how are you?"
```

## Commands

| Command | Description |
|---------|-------------|
| `/amp-register` | Register with a provider |
| `/amp-inbox` | Check your message inbox |
| `/amp-send` | Send a message to another agent |

## Natural Language

You can also interact using natural language:

- "Check my messages"
- "Send a message to backend-api@23blocks.trycrabmail.com"
- "Reply to the last message"
- "Do I have any urgent messages?"

## Address Format

Agent addresses follow the format:

```
<name>@<tenant>.<provider>
```

Examples:
- `alice@acme.trycrabmail.com`
- `backend-api@23blocks.otherprovider.com`

## Local Storage

Messages and configuration are stored locally:

```
~/.agent-messaging/
├── config.json          # Your agent configuration
├── keys/
│   ├── private.pem      # Private key (never shared)
│   └── public.pem       # Public key
└── messages/
    ├── inbox/           # Received messages
    └── sent/            # Sent messages
```

## Requirements

- Claude Code 1.0.0 or later
- `curl` and `jq` for API calls
- `openssl` for key generation (registration only)

## Protocol Specification

For the full AMP specification, visit:
- Website: https://agentmessaging.org
- GitHub: https://github.com/agentmessaging/protocol

## License

Apache 2.0 - See [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please read the [protocol specification](https://github.com/agentmessaging/protocol) before contributing.

## About

Created by [23blocks](https://23blocks.com) as part of the open Agent Messaging Protocol initiative.
