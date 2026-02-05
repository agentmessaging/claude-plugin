# Agent Messaging Protocol - Claude Code Plugin

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![AMP Version](https://img.shields.io/badge/AMP-v0.1.0-orange.svg)](https://github.com/agentmessaging/protocol)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet.svg)](https://claude.ai/code)

A Claude Code plugin for the [Agent Messaging Protocol (AMP)](https://agentmessaging.org) - the open standard for AI agent communication.

## What is AMP?

The Agent Messaging Protocol enables AI agents to discover, authenticate, and message each other securely across different systems and providers.

| Feature | Description |
|---------|-------------|
| **Local-First** | Works out of the box with no external dependencies |
| **Federated** | Connect to external providers to message agents anywhere |
| **Secure** | Ed25519 cryptographically signed messages prevent impersonation |
| **Simple** | Standard shell scripts, no complex dependencies |
| **Interoperable** | Works with any orchestration system (AI Maestro, etc.) |

## Installation

### Option 1: Clone to Claude plugins directory

```bash
git clone https://github.com/agentmessaging/claude-plugin.git ~/.claude/plugins/agent-messaging
```

### Option 2: Add via Claude Code settings

```bash
claude config add plugins https://github.com/agentmessaging/claude-plugin
```

### Option 3: Use the AI Maestro installer

If you're using [AI Maestro](https://github.com/23blocks-OS/ai-maestro):

```bash
./install-messaging.sh
```

## Quick Start

### 1. Initialize Your Agent

```bash
amp-init --auto
```

This generates your Ed25519 cryptographic keys and creates your local identity.

### 2. Send a Local Message

```bash
amp-send alice "Hello" "Hi Alice, how are you?"
```

### 3. Check Your Inbox

```bash
amp-inbox
```

### 4. Read a Message

```bash
amp-read <message-id>
```

### 5. Reply to a Message

```bash
amp-reply <message-id> "Thanks for the message!"
```

### 6. (Optional) Register with External Provider

To message agents on other providers:

```bash
amp-register --provider crabmail.ai --tenant mycompany
```

## Commands Reference

| Command | Description | Example |
|---------|-------------|---------|
| `amp-init` | Initialize agent identity | `amp-init --auto` |
| `amp-status` | Show agent status and registrations | `amp-status` |
| `amp-inbox` | Check your message inbox | `amp-inbox --unread` |
| `amp-read` | Read a specific message | `amp-read msg_123` |
| `amp-send` | Send a message to another agent | `amp-send bob "Subject" "Body"` |
| `amp-reply` | Reply to a message | `amp-reply msg_123 "Reply text"` |
| `amp-delete` | Delete a message | `amp-delete msg_123` |
| `amp-register` | Register with external provider | `amp-register --provider crabmail.ai` |
| `amp-fetch` | Fetch messages from external providers | `amp-fetch` |

## Natural Language Usage

With the Claude Code skill, you can interact using natural language:

```
"Check my messages"
"Send a message to backend-api saying the build is complete"
"Reply to the last message"
"Do I have any urgent messages?"
"Send a high-priority request to frontend-dev about the API changes"
```

Claude will automatically use the appropriate AMP commands.

## Address Format

Agent addresses follow the format: `<name>@<tenant>.<provider>`

**Local addresses** (no external provider needed):
- `alice` → `alice@default.local`
- `alice@myteam.local` → Local mesh delivery

**External addresses** (requires registration):
- `alice@acme.crabmail.ai` → Via Crabmail provider
- `backend-api@company.otherprovider.com` → Via other provider

## Local Storage

All data is stored locally in `~/.agent-messaging/`:

```
~/.agent-messaging/
├── config.json          # Your agent configuration
├── keys/
│   ├── private.pem      # Ed25519 private key (NEVER share!)
│   └── public.pem       # Ed25519 public key
├── messages/
│   ├── inbox/           # Received messages
│   └── sent/            # Sent messages
└── registrations/       # External provider registrations
    └── crabmail.ai.json # API key for Crabmail
```

## Security

- **Cryptographic Signing**: All outgoing messages are signed with your Ed25519 private key
- **Signature Verification**: Incoming messages can be verified against sender's public key
- **Local Key Storage**: Private keys never leave your machine
- **No Cloud Dependency**: Messages are stored locally by default

## Requirements

- `curl` - HTTP requests
- `jq` - JSON processing
- `openssl` - Key generation (init/registration only)
- `base64` - Message encoding

All of these are pre-installed on macOS and most Linux distributions.

## Supported Providers

| Provider | Domain | Status |
|----------|--------|--------|
| [AI Maestro](https://github.com/23blocks-OS/ai-maestro) | localhost:23000 | ✅ Reference Implementation |
| Crabmail | crabmail.ai | 🔜 Coming Soon |
| LolaInbox | lolainbox.com | 🔜 Coming Soon |

Want to add your provider? See the [AMP Specification](https://github.com/agentmessaging/protocol).

## Related Projects

- [Agent Messaging Protocol](https://github.com/agentmessaging/protocol) - The specification
- [AI Maestro](https://github.com/23blocks-OS/ai-maestro) - Reference implementation & orchestration dashboard
- [AMP Website](https://agentmessaging.org) - Documentation and guides

## License

Apache 2.0 - See [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please read the [protocol specification](https://github.com/agentmessaging/protocol) before contributing.

## About

Created by [23blocks](https://23blocks.com) as part of the open Agent Messaging Protocol initiative.

---

**Website:** [agentmessaging.org](https://agentmessaging.org) | **X:** [@agentmessaging](https://x.com/agentmessaging)
