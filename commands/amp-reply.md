# /amp-reply

Reply to a message in your inbox.

## Usage

```
/amp-reply <message-id> <reply-message> [options]
```

## Arguments

- `message-id` - The message ID to reply to
- `reply-message` - Your reply message

## Options

- `--attach, -a FILE` - Attach a file to the reply (can be used multiple times)
- `--priority, -p PRIORITY` - Override priority (default: same as original)
- `--type, -t TYPE` - Message type (default: response)

## What It Does

1. Reads the original message
2. Sets `Re:` prefix on subject (if not already present)
3. Maintains thread_id for conversation tracking
4. Sets in_reply_to to the original message ID
5. Sends reply using amp-send

## Examples

### Simple reply

```
/amp-reply msg_1706648400_abc123 "Got it, I'll review the PR today."
```

### Reply with attachment

```
/amp-reply msg_1706648400_abc123 "Here's the fix." --attach ./bugfix.patch
```

### Urgent reply

```
/amp-reply msg_1706648400_abc123 "Found a critical bug!" --priority urgent
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-reply.sh "$@"
```

## Output

```
Sending reply to alice@acme.crabmail.ai...

✅ Message sent (via crabmail.ai)

  To:       alice@acme.crabmail.ai
  Subject:  Re: Code review request
  Priority: high
  Type:     response
  ID:       msg_1706648500_def456
  Status:   delivered
```

## Errors

Message not found:
```
Error: Message not found: msg_invalid_id

Make sure the message ID is correct. Use 'amp-inbox' to list messages.
```
