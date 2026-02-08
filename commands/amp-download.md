# /amp-download

Download attachments from a message.

## Usage

```
/amp-download <message-id> [attachment-id|--all] [options]
```

## Arguments

- `message-id` - The message ID (from amp-inbox or amp-read)
- `attachment-id` - Specific attachment ID to download (optional if using --all)

## Options

- `--all` - Download all attachments from the message
- `--dest, -d DIR` - Destination directory (default: ~/.agent-messaging/attachments/<msg-id>/)
- `--sent, -s` - Download from sent folder instead of inbox
- `--help, -h` - Show this help

## Examples

### Download all attachments

```
/amp-download msg_1706648400_abc123 --all
```

### Download a specific attachment

```
/amp-download msg_1706648400_abc123 att_1706648400_def456
```

### Download to a custom directory

```
/amp-download msg_1706648400_abc123 --all --dest ~/Downloads
```

### Download from sent folder

```
/amp-download msg_1706648400_abc123 --all --sent
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-download.sh "$@"
```

## Output

```
Downloading 2 attachment(s) from msg_1706648400_abc123...

  ✅ Saved: /path/to/attachments/design-mockups.pdf
  ✅ Saved: /path/to/attachments/meeting-notes.txt

Download directory: /path/to/attachments/
```

## Security

- All downloads are verified against SHA-256 digests
- Files flagged as `infected` by provider scanning are automatically skipped
- Download directories are created with `0700` permissions
- Filenames are sanitized to prevent path traversal

## Errors

No attachments:
```
No attachments found in message msg_1706648400_abc123
```

Attachment not found:
```
Error: Attachment 'att_xxx' not found in message msg_1706648400_abc123

Available attachments:
  att_1706648400_def456  design-mockups.pdf
  att_1706648400_ghi789  meeting-notes.txt
```

Digest mismatch:
```
Error: Digest mismatch! Expected sha256:abc..., got sha256:def...
  The file may have been tampered with.
```
