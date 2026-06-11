# Contributing to sendorbit

Thanks for your interest in contributing!

## Reporting bugs / suggesting features

1. Open an **Issue** on GitHub
2. Use a clear, descriptive title
3. Include:
   - sendorbit version (`1.0.0`)
   - OS and Bash version (`bash --version`)
   - Steps to reproduce
   - Expected vs actual behavior

## Submitting changes (Pull Request)

1. Fork the repository
2. Create a branch with a descriptive name:
   ```bash
   git checkout -b feature/new-feature
   ```
3. Make your changes following the current code style
4. Ensure ShellCheck passes (`shellcheck --severity=warning sendorbit.sh lib/*.sh modules/*.sh`) and BATS tests pass (`bats tests/*.sh`)
5. Update `CHANGELOG.md` under `[Unreleased]`
6. Open a Pull Request with a clear description

## Code guidelines

- Use `set -euo pipefail` in all scripts
- Keep functions modular
- Document new functions
- Do not introduce external dependencies

Any contribution is welcome!