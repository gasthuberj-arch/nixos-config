# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` is the entry point for NixOS configurations and outputs.
- `hosts/` holds host-specific configs (for example `hosts/homelab/configuration.nix`).
- `modules/` contains reusable Nix modules; service modules live in `modules/services/`.
- `disko/` and `hosts/*/disko-config.nix` define storage layout.
- `docs/` contains setup guides and ADRs; `docs/adr/` tracks architecture decisions.
- `scripts/` contains helper scripts for validation and setup.

## Build, Test, and Development Commands
- `nix fmt` formats the repository using Alejandra (see `flake.nix` formatter).
- `nixos-rebuild switch --flake .#homelab` applies the configuration locally (requires root).
- `./deploy.sh --ip 192.168.1.100` copies the config to a remote host and rebuilds.
- `nix build .#iso` builds the installer ISO defined in `flake.nix`.
- `scripts/check-authelia-v2.sh` renders and validates the Authelia config.

## Coding Style & Naming Conventions
- Nix files use 2-space indentation and standard Nix formatting; run `nix fmt`.
- Service modules are named `modules/services/<service>.nix` (lowercase, kebab-case if needed).
- Keep host-specific overrides in `hosts/<host>/configuration.nix` and avoid duplication in modules.

## Testing Guidelines
- There is no automated test suite in this repo.
- Use targeted validation scripts where available (for example `scripts/check-authelia-v2.sh`).
- For service changes, update relevant docs in `docs/` and verify the service module builds.

## Commit & Pull Request Guidelines
- Recent commits are short, imperative sentences (for example “Enable couchDB sync for Obsidian”).
- Keep commits focused on a single change; include the affected host/service in the message when helpful.
- Enable repo hooks once: `git config core.hooksPath .githooks` (required for pre-commit formatting).
- PRs should describe the change, impacted hosts/services, and any required manual steps.
- Link related docs or ADRs when introducing new architecture decisions.

## Security & Configuration Tips
- Do not commit secrets. Use `sops-nix` and per-host secret setup scripts.
- `scripts/setup-secrets.sh` prepares secrets on the target host; run it before deployment when needed.
