# Contributing to sendorbit

Thanks for your interest in contributing!

## Reporting bugs / suggesting features

1. Open an **Issue** on GitHub
2. Use a clear, descriptive title
3. Include:
   - sendorbit version (run `./sendorbit.sh --version`)
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

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) style:
`type(scope): summary` — e.g. `fix(cli): ...`, `feat(validation): ...`,
`docs: ...`, `test: ...`, `chore(release): ...`. Keep the summary in English,
imperative mood, under ~72 characters. The scope is optional but should name
the touched area (`cli`, `tui`, `transfer`, `validation`, `logging`, `ci`, …).

## Code guidelines

- Use `set -euo pipefail` in entrypoint scripts and modules (sourced libs
  inherit the caller's shell options)
- Keep functions modular
- Document new functions — comments explain *why* (constraints, invariants),
  never narrate the obvious
- No hardcoded version strings outside `lib/utils.sh` (`VERSION`)
- All interactive input goes through `safe_read` (`lib/utils.sh`)
- Do not introduce external dependencies

Any contribution is welcome!