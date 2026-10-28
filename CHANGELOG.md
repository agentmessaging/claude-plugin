# Changelog

## 0.5.2

### Security: review and updates, 2026-10-28

Reviewed all scripts with shellcheck and by hand, searched git history for committed secrets (none found), and ran `npm audit` (0 vulnerabilities). Changes, all backward compatible:

- `scripts/amp-helper.sh`: `save_to_inbox` and `save_to_sent` refuse a message id that is not a plain token (`^[a-zA-Z0-9][a-zA-Z0-9_-]{3,63}$`, the pattern `amp-fetch.sh` already used). The id comes from the sender and became a file name, so `../` ids could write outside the inbox.
- `scripts/amp-helper.sh`: replay check matches the whole id (`grep -qF -- "<id>|"`), not any substring, and an id starting with `-` is no longer read as a grep option.
- `scripts/amp-helper.sh`: attachment download from a message-supplied URL must start with `http://` or `https://`, is passed with `--url` (so it cannot be read as a curl option), and redirects are limited to http(s).
- `scripts/amp-helper.sh`: private keys are generated under `umask 077`; the rotation temp dir is `0700`; `ensure_amp_dirs` sets the agent dir and `registrations/` (which holds provider API keys) to `0700`.
- `scripts/amp-register.sh`, `amp-init.sh`, `amp-send.sh`: registration files holding the API key are created `0600` before they are written, not chmod-ed afterwards.
- `scripts/amp-helper.sh`: replay-db prune uses `mktemp` instead of a PID-based name; `compute_expiry_date` ignores non-numeric day counts (SC2086).
- `scripts/amp-fetch.sh`: an empty provider on either side no longer counts as "same provider" when deciding to trust a fetched message.
- CI: workflow `permissions: contents: read`; Node 20 (end of life) replaced by Node 22; `actions/checkout` and `actions/setup-node` updated to v7.
- Tests: `tests/unit/security_hardening.bats` (10 tests) covers the id, key-mode, directory-mode and URL checks above.

Not changed: `save_to_inbox` still treats a sender whose claimed address is on the local provider domain as trusted without checking a signature, because callers rely on it (see the TODO at that code); the provider is expected to verify at ingest.
