---
status: "accepted"
date: 2026-11-13
decision-makers: Johannes Gasthuber
consulted: N/A
informed: Future administrators, documentation readers
---

# Production Security Hardening Baseline Across Multi-Host NixOS Fleet

## Context and Problem Statement

The `nixos-config` repository manages a multi-architecture NixOS fleet (`homelab`, `work-laptop`, `personal-laptop` on `x86_64-linux`, and `rpi5`, `orin-nx` on `aarch64-linux`) in a public Git repository. Previously, several gaps weakened defense-in-depth:

1. Plaintext fallback passwords (such as Nextcloud's `pkgs.writeText "nextcloud-admin-pass" "changeme"`) could be written into the world-readable `/nix/store`.
2. `sops-nix` lacked a fleet-wide per-host key hierarchy, risking shared decryption scopes across edge nodes and core infrastructure.
3. `homelab` persisted the entire `/var/lib` tree via a ZFS dataset and hardcoded service directories in `hosts/homelab/persistence.nix`.
4. Several backend services lacked explicit `127.0.0.1` loopback binding and reusable systemd sandboxing, while Sunshine/Steam gaming workloads shared the host filesystem and firewall without isolation.
5. GitHub Actions CI enabled `accept-flake-config = true`, allowing flake inputs to inject untrusted binary cache substituters.

## Decision Drivers

* **Zero Nix Store Secret Leaks:** Enforce runtime-only secret files (`/run/secrets/*` or `/persist/secrets/*`) with evaluation-time assertions rejecting `/nix/store` paths.
* **Per-Host Blast-Radius Isolation:** Partition SOPS encryption per host via `.sops.yaml` creation rules and per-host `ssh_host_ed25519_key`-derived `age` keys.
* **Granular Impermanence Without Coupling:** Allow service modules to declare their own `/var/lib/<service>` state paths via `homelab.persistence` without importing `impermanence` on non-impermanent hosts (`rpi5`, `orin-nx`, laptops).
* **Systemd Confinement With Hardware/JIT Escape Hatches:** Apply `ProtectSystem = "strict"`, `PrivateTmp = true`, `NoNewPrivileges = true`, and device/kernel restrictions uniformly while allowing per-service `allowJit` and `allowGpu` toggles.
* **Loopback Ingress & Workload Containment:** Restrict backend web/metrics listeners to `127.0.0.1` behind Caddy/Authelia, isolate Sunshine in `gaming.slice` with `InaccessiblePaths`, and provide RFC1918 egress isolation for microVM bridges.
* **Supply-Chain Hygiene:** Disable `accept-flake-config` in CI and automate weekly `flake.lock` updates.

## Considered Options

* **Option 1: Per-Module Hardening + Core Seam (`modules/core/hardening.nix`) + Per-Host SOPS**
* **Option 2: Ad-Hoc Hardening in Host Files Only**
* **Option 3: Hardcoded `environment.persistence` Inside Each Service Module**

## Decision Outcome

Chosen option: **Option 1 - Per-Module Hardening + Core Seam + Per-Host SOPS**, because it preserves module purity across impermanent and standard-disk hosts, eliminates secret leaks into `/nix/store`, enforces uniform systemd sandboxing, and isolates per-host credentials.

### Architecture Summary

1. **Core Security & Persistence Seam (`modules/core/hardening.nix`, `modules/core/base.nix`):**
   - Defines `homelab.persistence.{directories,files}` consumed by `hosts/homelab/persistence.nix`.
   - Exports `mkHardenedService` (`_module.args.mkHardenedService`) using `lib.mkDefault` so upstream NixOS service overrides merge without conflict.
   - Enforces kernel sysctl hardening, SSH key-only auth (`PasswordAuthentication = false`, `PermitRootLogin = "no"`), `homelab.hardening.secretPaths` store-leak assertions, and optional `homelab.hardening.microvmEgressIsolation` nftables drop rules for RFC1918 subnets.
2. **Per-Host SOPS Key Hierarchy (`.sops.yaml`, `secrets/<host>.yaml`):**
   - Each host (`homelab`, `work-laptop`, `personal-laptop`, `rpi5`, `orin-nx`) binds its own `secrets/<host>.yaml` file and SSH ed25519 host key (`/persist/etc/ssh/ssh_host_ed25519_key` on `homelab`, `/etc/ssh/ssh_host_ed25519_key` elsewhere).
3. **Service Hardening & Loopback Locking (`modules/services/*.nix`):**
   - Caddy admin (`127.0.0.1:2019`), Immich, Paperless, Nextcloud nginx, Grafana, Prometheus, Exporters, Loki, Alloy, Gatus, Vaultwarden, Home Assistant, and CouchDB bind strictly to `127.0.0.1`.
   - Nextcloud, Paperless, Immich, and Grafana generate runtime secrets under `/persist/secrets/*` instead of writing defaults to `/nix/store`.
   - Sunshine runs under `gaming.slice` with `InaccessiblePaths` blocking `/persist/secrets`, `/run/secrets`, and core service state directories; LAN firewall ports for Sunshine and Steam Remote Play default to `false` (accessible via Tailscale).
4. **Granular Impermanence & Mount Hardening (`hosts/homelab/`):**
   - Removes blanket `nixos/var/lib` ZFS dataset and `fileSystems."/var/lib"` persistence; adds `nosuid` and `nodev` (`setuid = "off"; devices = "off";`) to `/persist`, `/home`, and ZFS data datasets.
5. **CI Supply-Chain Hardening (`.github/workflows/`):**
   - Sets `accept-flake-config = false` in `ci.yml` with pinned binary cache keys and adds weekly `flake-update.yml`.

### Consequences

* **Good:** Compromising a single host or service no longer exposes fleet-wide secrets, `/nix/store` plaintext passwords, or core service databases.
* **Good:** `homelab` root impermanence wipes any undeclared `/var/lib` artifacts on reboot.
* **Bad:** Removing blanket `/var/lib` persistence requires running `scripts/audit-var-lib-persistence.sh --migrate` on `homelab` before the first reboot after cutover.
* **Neutral:** Enrolling real host keys requires running `scripts/setup-secrets.sh --enroll-age-key` on each host, updating `.sops.yaml`, and running `sops updatekeys secrets/*.yaml`.

### Confirmation

* `nix flake check --no-build` evaluates all `x86_64-linux` and `aarch64-linux` configurations cleanly.
* `nix build .#checks.x86_64-linux.pre-commit-check` passes `alejandra`, `statix`, `deadnix`, and `gitleaks`.
* `./scripts/check-authelia-v2.sh` validates the rendered Authelia configuration.
* `nix eval --json --apply 'map (d: d.directory)' .#nixosConfigurations.homelab.config.environment.persistence.\"/persist\".directories` outputs all declared service state directories.
* On live hosts, `systemd-analyze security <unit>` verifies reduced exposure scores, and `scripts/audit-var-lib-persistence.sh --dry-run` diffs `/var/lib` against declared persistence paths before rebooting.
