# sendorbit Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2026-09-07

### Security

- `init_system` sanitizes `PATH` before any external command runs, so binaries are
  always resolved from `/usr/local/bin:/usr/bin:/bin` and never from a hostile
  inherited `PATH`.
- Log writes neutralize line breaks and tabs, so hostile input cannot forge
  additional log entries.
- The rsync backup store is excluded from the sync source, preventing a nested
  backup directory from being re-transferred on subsequent pushes.
- `#` inside quoted `hosts.conf` values is rejected instead of being silently
  truncated at the comment strip.
- The `--transfer` type is whitelisted before any branch (including `--dry-run`)
  echoes it.

### Fixed

- Modules invoked directly now acquire the single-instance lock and write the
  session-start security entry, exactly like the main entrypoint.
- TUI file input aborts with guidance when a single existing filename contains
  spaces, instead of silently transferring the space-separated parts.
- Logs (general and security) are rotated when a session closes, not only at
  startup; long-running sessions no longer grow a single unbounded log.
- Empty port arguments (`--connect u h ""`) are rejected instead of silently
  falling back to port 22.
- CLI validates argument counts and rejects unknown flags: `--connect`/`--transfer`
  with missing arguments print usage and exit 1 instead of mis-parsing.
- Validators force a C locale so locale-dependent character classes cannot let
  accented characters slip through host/user validation.

### Changed

- CI pins ShellCheck 0.9.0 and bats 1.10.0.
- Docs hygiene pass: removed private audit references from code comments and test
  names, fixed wrong or dangling comments, aligned the startup banner output with
  the documented example, documented `-v`/`-h` short flags, and synced
  README/SECURITY/CONTRIBUTING/AGENTS with actual behavior.

## [1.0.3] - 2026-08-24

### Changed

- Hostnames longer than 253 characters are rejected by `validate_hostname` (RFC 1035 limit).
- Ports with leading zeros (`0080`) are rejected by `validate_port`, consistent with IP-octet handling.
- Documented that command overrides (`SSH_CMD`/`SCP_CMD`/`RSYNC_CMD`) apply only on direct module invocation; `sendorbit.sh` always resolves binaries from its sanitized PATH.
- Docs hygiene: removed hardcoded version strings outside `lib/utils.sh` (CONTRIBUTING), refreshed example-session banner and unit-test count.

## [1.0.2] - 2026-08-24

### Security

- Reject control characters (newline/TAB/CR) in destination paths at every layer, including
  the `transfer` module, preventing remote-shell injection via legacy scp and multi-line log
  forgery.
- Enforce `validate_folder_path` in `modules/transfer.sh` (standalone entrypoint invariant).

### Fixed

- Log rotation no longer aborts the whole program under `set -e` when `stat` lacks GNU `-c`
  support (BSD/macOS).
- Transfer file-list prompt now goes through `safe_read` (input invariant).
- Config parser detects multi-line array close from the current line instead of stale state.

## [1.0.1] - 2026-08-22

### Added

- `--push-dir` flag to send the current working directory to a configured host
  (rsync + backup by default, `--scp` to force SCP, `--dry-run` to preview).
- `validate_port` and `validate_folder_path` shared validators; CLI entry points
  (`--connect`, `--transfer`) now enforce the same port/destination rules as
  `config/hosts.conf` entries.
- `SECURITY.md` with reporting policy and security model summary.

### Changed

- Remote backups use native `rsync --backup --backup-dir=<timestamp>` instead of a
  per-file remote `cp` loop: backups are now recursive, cover directory pushes
  (`--push-dir`) and never collide on duplicate basenames. The backup directory is
  created first via `%q`-quoted `mkdir -p`; if that fails the transfer **aborts**
  instead of proceeding without backup.
- General log (`logs/sendorbit.log`) is created with `600` permissions and `umask 077`
  is applied at startup (previously world-readable depending on umask).
- Interactive prompts survive EOF (Ctrl-D) and timeouts under `set -euo pipefail`
  via a new `safe_read` helper; menus no longer spin forever or crash on closed input.

### Fixed

- Non-interactive `--transfer` misparsed its arguments since v1.0.0 (a double
  `shift` consumed the transfer type, shifting every field by one). `--dry-run`
  must now be followed by `--transfer`, as documented in `--help`.
- Lock file is no longer deleted at exit — unlinking it while another instance may
  hold the FD broke mutual exclusion (classic flock-unlink race).
- Missing `flock` binary now degrades gracefully with a warning instead of failing
  with a misleading "already running" message.
- Test suite count corrected in docs (was advertised as 100).

## [1.0.0] - 2026-06-11
