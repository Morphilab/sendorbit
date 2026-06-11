# sendorbit

[![CI](https://github.com/morphilab/sendorbit/actions/workflows/test.yml/badge.svg)](https://github.com/morphilab/sendorbit/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash 4.3+](https://img.shields.io/badge/bash-4.3%2B-blue.svg)](https://www.gnu.org/software/bash/)

Modular SSH connection and SCP/RSync transfer manager written in Bash. Delegates all SSH behavior to native OpenSSH (`~/.ssh/config`).

## Features

- SSH connection (delegates all options to `~/.ssh/config` — timeouts, keepalive, compression, multiplexing, host-key verification)
- SCP and RSync transfers with automatic timestamped backup on the remote
- Anti-injection input validation (path traversal, shell metacharacters, argument injection)
- Dual logging (general + security) with 10MB rotation (5 files max)
- Configurable colors, no hardcoded values
- Lock file via `flock` (no TOCTOU / symlink races)
- Config parser uses text-only extraction — no `source`/`eval` on user config
- PATH sanitized before resolving binaries
- 100 BATS unit tests + CI on every push

## ⚠️ AI Disclosure / Divulgación de IA

**English:**  
This project was developed with assistance from artificial intelligence tools. Given the automated nature of some components, users are advised to review and test the code independently before integrating it into their own systems.

**Español:**  
Este proyecto fue desarrollado con asistencia de herramientas de inteligencia artificial. Dada la naturaleza automatizada de algunos componentes, se recomienda que los usuarios revisen y prueben el código independientemente antes de integrarlo en sus propios sistemas.

## Requirements

- Bash 4.3+
- `ssh`, `scp`, `rsync`
- [bats](https://github.com/bats-core/bats-core) (optional, for running the test suite)

## Installation

```bash
git clone https://github.com/morphilab/sendorbit.git
cd sendorbit
cp config/example_hosts.conf config/hosts.conf
chmod 600 config/hosts.conf
# edit config/hosts.conf with your servers
./sendorbit.sh
```

## Quick start

1. Configure your hosts:
   ```bash
   cp config/example_hosts.conf config/hosts.conf
   chmod 600 config/hosts.conf
   $EDITOR config/hosts.conf
   ```

2. Run interactively:
   ```bash
   ./sendorbit.sh
   ```

3. Check version or help:
   ```bash
   ./sendorbit.sh --version
   ./sendorbit.sh --help
   ```

## Example session

```
$ ./sendorbit.sh

╔════════════════════════════════════════════╗
║              sendorbit v1.0.0              ║
╚════════════════════════════════════════════╝

Available hosts:
 1. admin@1xx.1xx.1.1xx:22 -> /home/admin/backups
 2. deploy@prod-web:2222 -> /var/www/app
 3. ops@duckpi.local -> /home/monkey/duckpi

Host (1-3) or 'q' to quit: 2

SELECTED HOST
User      : deploy
Host      : prod-web:2222
Destination: /var/www/app

Available actions:
 1. Connect SSH
 2. Send files (SCP)
 3. Smart sync (RSync + automatic backup)
 4. View system logs
 5. Exit

Select action (1-5): 1
Connect to deploy@prod-web:2222? (y/N): y
Connecting to deploy@prod-web:2222...
[...SSH session...]
Connection closed successfully
```

## hosts.conf format

```bash
# 3 fields: user host folder (port 22)
"admin 1xx.1xx.1.1xx backups"

# 4 fields: user host folder port
"admin server.com /home/admin/deploy 2222"
```

`host` accepts IPs, DNS hostnames, or `~/.ssh/config` aliases. The `user` in `hosts.conf` must match the `User` defined in `~/.ssh/config` for aliases.

## Security

- SSH configuration delegated entirely to `~/.ssh/config` (no hardcoded options that override user settings)
- Hosts rejected if they contain shell metacharacters (`;&|<>`, `(){}`, `` ` ``, `$`, `!`, `[]`, `*`, `?`, `~`, newlines, tabs) or path traversal (`..`)
- Transfers protected by anti-argument-injection delimiter `--`
- Config parser extracts entries text-only (no `source`/`exec` of user-supplied data)
- PATH sanitized to `/usr/local/bin:/usr/bin:/bin` before binary resolution
- Lock file via `flock -n` over file descriptor (no TOCTOU/symlink attacks)
- Security log with 600 permissions, audit trail of all connection attempts
- No eval, no dynamic source from user input

## SSH delegation model

sendorbit does **not** inject any SSH options of its own. To configure timeouts, keepalive, compression, host-key verification, or `ProxyJump`, edit `~/.ssh/config`:

```sshconfig
Host prod-web
    HostName 203.0.113.50
    User deploy
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    ConnectTimeout 30
    ServerAliveInterval 60
    StrictHostKeyChecking accept-new
```

Passphrase-protected keys work if loaded in `ssh-agent`. Without an agent, SSH will prompt interactively for the passphrase.

## Project structure

```
sendorbit.sh            → entrypoint (interactive TUI + non-interactive CLI)
lib/utils.sh            → utilities, colors, output, parsing
lib/validation.sh       → centralized validations (no source/exec)
lib/logging.sh          → logging with rotation
lib/security.sh         → input validation, security logging
modules/connection.sh   → SSH connection
modules/transfer.sh     → SCP/RSync with backup
config/                 → hosts.conf (gitignored)
logs/                   → sendorbit.log, security.log (gitignored)
tests/                  → bats unit tests (100 tests)
```

## Running tests

```bash
bats tests/validation_test.sh
bats tests/security_test.sh
bats tests/logging_test.sh
bats tests/modules_test.sh
```

Or run all suites at once:

```bash
bats tests/*.sh
```

CI runs `bash -n`, ShellCheck, and the full BATS suite on every push and PR.

## License

[MIT](LICENSE) — Copyright (c) 2026 morphilab
