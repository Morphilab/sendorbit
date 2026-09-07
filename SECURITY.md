# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | yes       |

## Reporting a vulnerability

Please do **not** open a public GitHub issue for security reports.

1. Open a [private security advisory](https://github.com/morphilab/sendorbit/security/advisories/new), or
2. Contact the maintainer directly (see the GitHub profile of `morphilab`).

Include: affected version, reproduction steps, and impact assessment. You will
receive an initial response within 7 days. Fixes are released as patch versions.

## Threat model

sendorbit is a single-user, local-first tool. It assumes:

- The local user running it is trusted (it executes SSH with their privileges).
- The remote accounts configured in `config/hosts.conf` are trusted endpoints.
- `config/hosts.conf`, `~/.ssh/config` and the logs directory are only writable by
  the owning user (the tool enforces `600` on sensitive files and `umask 077`).

Out of scope by design: multi-user hardening, protecting against a malicious
remote host that has already compromised the destination account.

## Security controls

- **No code execution from user config**: `config/hosts.conf` is parsed text-only
  via regex extraction — never `source`d or `eval`'d.
- **Input whitelisting**: users (`^[a-zA-Z_][a-zA-Z0-9_-]*$`, ≤32 chars, no
  trailing hyphen), hosts
  (strict IP/hostname grammar plus shell-metacharacter blacklist), ports
  (`validate_port`, 1–65535) and destination paths (`validate_folder_path`,
  traversal + metacharacter rejection). Applied at every entry point: TUI, CLI
  flags and both modules.
- **Argument injection**: file arguments are always passed after `--` in scp/rsync.
- **Remote command hygiene**: the remote backup directory is created through a
  `%q`-quoted `mkdir -p`; if creation fails the transfer aborts instead of
  proceeding unprotected.
- **PATH sanitization**: restricted to `/usr/local/bin:/usr/bin:/bin` before any
  binary is resolved; modules re-sanitize on startup.
- **Single-instance lock**: `flock -n` over a dedicated FD; the lockfile is never
  unlinked at runtime (flock-unlink race prevention). Without `flock`, the main
  entrypoint degrades with a warning; directly invoked modules proceed without
  the lock (silently).
- **Logging**: dual logs with rotation; general log forced to `600`; `umask 077`
  at startup; security log records connections, transfers and rejections.

## Known limitations

- No IPv6 literal support (hostnames/IPv4 only).
- Filenames containing spaces cannot be passed through the interactive prompt
  (word-split input); use non-interactive `--transfer` for those.
