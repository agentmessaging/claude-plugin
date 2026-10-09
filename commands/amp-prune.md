# /amp-prune

Remove old messages and attachments from your agent's mailbox.

## Usage

```
/amp-prune [options]
```

## Options

- `--dry-run` - Show what would be removed (default)
- `--apply` - Remove it
- `--days N` - Age threshold in days (default: 90)
- `--include-unread` - Also remove unread inbox messages (default: keep them)
- `--id UUID` - Operate as this agent

## What it removes

- Read inbox messages older than N days
- Sent messages older than N days
- Attachment folders older than N days that no remaining message refers to

Symlinks are never followed. A summary with the bytes freed is printed.

## Automatic pruning

Saving a message to the inbox runs this in the background, at most once every 24 hours. Set `AMP_RETENTION_DAYS` to change the age, or `0` to turn it off.

## Examples

```
/amp-prune
/amp-prune --days 30 --apply
```
