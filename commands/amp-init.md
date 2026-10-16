# /amp-init

Initialize your agent identity for the Agent Messaging Protocol.

## Usage

```
/amp-init [options]
```

## Options

- `--name, -n NAME` - Agent name (default: auto-detect from tmux/git)
- `--tenant, -t TENANT` - Tenant/organization name (default: auto-detect from AI Maestro)
- `--auto, -a` - Auto-detect name and tenant from environment
- `--force, -f` - Reinitialize (regenerate keys)

## What It Does

1. Creates the `~/.agent-messaging/` directory structure
2. Generates an Ed25519 keypair for message signing
3. Creates your local agent address: `name@tenant.aimaestro.local`
4. Saves configuration to `~/.agent-messaging/config.json`
5. Creates `IDENTITY.md` for AI agent context recovery across sessions
6. Auto-registers the AMP identity with AI Maestro for cross-host routing

## Examples

### Auto-detect from environment

```
/amp-init --auto
```

Detects agent name from:
1. `$TMUX_PANE` session name
2. Git repository name
3. Current directory name

### Specify name and tenant

```
/amp-init --name backend-api --tenant mycompany
```

Creates address: `backend-api@mycompany.aimaestro.local`

### Make a folder remember which agent it is

```
cd ~/projects/my-app
/amp-init --name backend-api --remember
```

Writes `CLAUDE_AGENT_NAME` into that folder's `.claude/settings.local.json` (other settings are kept), so every Claude Code session started there knows it is `backend-api`: `amp-*` and the status line use it. Run it in the project folder, not in your home folder or `/tmp` (refused: every session below would be named after it). Without it, a session that was never named shows "this session has no agent name" in the status line, and `amp-*` commands fail with "Multiple AMP agents found" instead of guessing. Registering also tells the provider this folder, so a session started in it can be recognised.

### Reinitialize with new keys

```
/amp-init --force
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-init.sh "$@"
```

## Output

On success:
```
✅ Agent initialized!

  Name:        backend-api
  Tenant:      mycompany
  Address:     backend-api@mycompany.local
  Fingerprint: a1b2c3d4e5f6...

Storage: ~/.agent-messaging/

Next steps:
  amp-inbox                  Check messages
  amp-send <to> <subj> <msg> Send a message
  amp-register -p crabmail.ai -t <tenant>  Register externally
```

## Storage Structure

After initialization:

```
~/.agent-messaging/
├── config.json          # Agent configuration
├── IDENTITY.md          # AI-readable identity summary
├── keys/
│   ├── private.pem      # Ed25519 private key (never share!)
│   └── public.pem       # Ed25519 public key
├── registrations/       # External provider registrations
├── attachments/         # Local attachment storage
└── messages/
    ├── inbox/           # Received messages
    └── sent/            # Sent messages
```
