# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` is the entry point for NixOS configurations and outputs.
- `hosts/` holds host-specific configs (for example `hosts/homelab/configuration.nix`).
- `modules/` contains reusable Nix modules; service modules live in `modules/services/`.
- `disko/` and `hosts/*/disko-config.nix` define storage layout.
- `docs/` contains setup guides and ADRs; `docs/adr/` tracks architecture decisions.
- `scripts/` contains helper scripts for validation and setup.

## Build, Test, and Development Commands
- `nix develop` drops into the development shell with active pre-commit hooks.
- `nix run nixpkgs#alejandra -- .` (or `alejandra .`) formats the repository rapidly.
- `nix build .#checks.x86_64-linux.pre-commit-check` runs the full pre-commit test suite (Alejandra, Gitleaks, Statix, Deadnix).
- `nix flake check --no-build` verifies flake evaluation across all hosts.
- `nixos-rebuild switch --flake .#homelab` applies the configuration locally (requires root).
- `./deploy.sh homelab --ip 192.168.1.101` copies the config to a remote host and rebuilds.
- `nix build .#iso` builds the installer ISO defined in `flake.nix`.
- `scripts/check-authelia-v2.sh` renders and validates the Authelia config.

## Coding Style & Naming Conventions
- Nix files use 2-space indentation and standard Nix formatting; format with Alejandra.
- Service modules are named `modules/services/<service>.nix` (lowercase, kebab-case if needed).
- Keep host-specific overrides in `hosts/<host>/configuration.nix` and avoid duplication in modules.

## Testing & Quality Guidelines
- Automated pre-commit checks enforce: formatting (`alejandra`), secret scanning (`gitleaks`), unused code (`deadnix`), and anti-patterns (`statix`).
- Remote CI runs on all pushes and pull requests to `main`.
- Use targeted validation scripts where available (for example `scripts/check-authelia-v2.sh`).
- For service changes, update relevant docs in `docs/` and verify the service module builds.

## Commit & Pull Request Guidelines
- Recent commits are short, imperative sentences (for example “Enable couchDB sync for Obsidian”).
- Keep commits focused on a single change; include the affected host/service in the message when helpful.
- Repo hooks are automatically configured when using `direnv` / `nix develop` or by setting `git config core.hooksPath .githooks`.
- PRs should describe the change, impacted hosts/services, and any required manual steps.
- Link related docs or ADRs when introducing new architecture decisions.

## Security & Configuration Tips
- Do not commit secrets. Use `sops-nix` and per-host secret setup scripts.
- `scripts/setup-secrets.sh` prepares secrets on the target host; run it before deployment when needed.
