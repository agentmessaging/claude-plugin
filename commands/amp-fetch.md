# /amp-fetch

Fetch new messages from external AMP providers.

## Usage

```
/amp-fetch [options]
```

## Options

- `--provider, -p PROVIDER` - Fetch from specific provider only
- `--verbose, -v` - Show detailed output
- `--no-mark` - Don't acknowledge messages on provider

## What It Does

1. Connects to each registered external provider
2. Downloads new messages not already in local inbox
3. Acknowledges receipt (optional, for message tracking)
4. Stores messages locally in `~/.agent-messaging/messages/inbox/`

## Examples

### Fetch from all providers

```
/amp-fetch
```

### Fetch from specific provider

```
/amp-fetch --provider crabmail.ai
```

### Verbose output

```
/amp-fetch --verbose
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-fetch.sh "$@"
```

## Output

Normal:
```
✅ Fetched 3 new message(s)

View messages: amp-inbox
```

Verbose:
```
Fetching from crabmail.ai...
  API: https://api.crabmail.ai
  Address: backend-api@23blocks.crabmail.ai
  Found 3 new message(s)
    Saved: msg_1706648400_abc123
      From: alice@acme.crabmail.ai
      Subject: Code review request
    Saved: msg_1706648410_def456
      From: bob@other.crabmail.ai
      Subject: Question about API
    Saved: msg_1706648420_ghi789
      From: system@crabmail.ai
      Subject: Welcome to Crabmail

✅ Fetched 3 new message(s)

View messages: amp-inbox
```

No new messages:
```
No new messages from external providers.
```

## Errors

Not registered:
```
Error: Not registered with crabmail.ai

Register first: amp-register --provider crabmail.ai
```

Authentication failed:
```
Error: Authentication failed for crabmail.ai
  Your API key may have expired. Re-register with:
  amp-register --provider crabmail.ai --force
```

Connection failed:
```
Error: Could not connect to crabmail.ai
  Check your internet connection.
```
