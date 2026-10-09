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

Off by default. Set `AMP_RETENTION_DAYS=N` and saving a message to the inbox runs this in the background, at most once every 24 hours. Unset, `0` or a non-number leaves it off.

## Examples

```
/amp-prune
/amp-prune --days 30 --apply
```
