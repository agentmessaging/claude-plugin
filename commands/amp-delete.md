# /amp-delete

Delete a message from your inbox or sent folder.

## Usage

```
/amp-delete <message-id> [options]
```

## Arguments

- `message-id` - The message ID to delete

## Options

- `--sent, -s` - Delete from sent folder (default: inbox)
- `--force, -f` - Delete without confirmation

## Examples

### Delete an inbox message

```
/amp-delete msg_1706648400_abc123
```

### Delete without confirmation

```
/amp-delete msg_1706648400_abc123 --force
```

### Delete a sent message

```
/amp-delete msg_1706648400_abc123 --sent
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-delete.sh "$@"
```

## Output

With confirmation:
```
Message to delete:

  ID:      msg_1706648400_abc123
  From:    alice@acme.crabmail.ai
  Subject: Code review request
  Date:    2025-02-02T10:30:00Z

Are you sure you want to delete this message? [y/N] y
✅ Message deleted
```

With --force:
```
Message to delete:

  ID:      msg_1706648400_abc123
  From:    alice@acme.crabmail.ai
  Subject: Code review request
  Date:    2025-02-02T10:30:00Z

✅ Message deleted
```

## Errors

Message not found:
```
Error: Message not found: msg_invalid_id

Check the message ID and folder (inbox/sent).
```
