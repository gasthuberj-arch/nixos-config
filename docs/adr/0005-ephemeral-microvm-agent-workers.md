---
status: "accepted"
date: 2026-11-13
decision-makers: Johannes Gasthuber
consulted: N/A
informed: Future administrators, documentation readers
---

# Ephemeral MicroVM Agent Workers (`agentDispatcher`)

## Context and Problem Statement

Running autonomous coding agents (such as `claude-code`, `opencode`, or `aider`) against GitHub issues requires executing untrusted, model-generated commands and builds (`nix develop`, `nix flake check`, `cargo`, `npm`). Running these directly on `homelab` exposes host filesystems, ZFS pools, `sops-nix` secrets, and internal `*.homelab.lan` services (Vaultwarden, Home Assistant, Nextcloud). At the same time, we want the exact same guest environment to run interactively on workstations via `nix run .#agent-vm-sandbox` for local experimentation.

## Decision Drivers

* **Hardware Virtualization Boundary:** Isolate untrusted agent execution behind a separate guest kernel via KVM rather than relying solely on Linux namespaces/containers.
* **Zero Persistence & Zero `/nix/store` Secret Leaks:** Keep all job state, cloned repos, writable store layers, and credentials in volatile RAM (`/run/agent-dispatcher/` on the host, `tmpfs` in the guest) and wipe them unconditionally on exit.
* **Least-Privilege GitHub Access:** Never place long-lived GitHub PATs or App private keys inside the VM; mint 1-hour, single-repository Installation Access Tokens on the host.
* **Zero-Trust LAN Isolation:** Allow public WAN egress (GitHub, LLM APIs, Nix caches) while blocking all access to RFC1918 subnets, Tailscale CGNAT (`100.64.0.0/10`), and the host itself.
* **Fast Iteration & Multi-Repo Support:** Support both `nix develop` / `nix flake check` inside `nixos-config` and general app repos without building multi-GB disk images per run.

## Considered Options

* **Option 1: `cloud-hypervisor` microVMs (`microvm.nix`) + `virtiofs` `/nix/store` + `tmpfs` overlay + `nftables` isolation table**
* **Option 2: `firecracker` microVMs with `erofs` store disk images**
* **Option 3: Rootless Docker / systemd-nspawn containers**

## Decision Outcome

Chosen option: **Option 1 - `cloud-hypervisor` microVMs with `virtiofs` `/nix/store` + `tmpfs` overlay + `nftables` isolation table**, because it provides a full KVM hardware boundary, boots in seconds by sharing the host's `/nix/store` read-only via `virtiofs` with an in-RAM `writableStoreOverlay`, and layers cleanly alongside `homelab`'s existing firewall without disturbing Tailscale or Docker.

### Architecture Summary

1. **Guest MicroVM ([agent-worker.nix](../../modules/microvms/agent-worker.nix)):**
   - Dual-mode boot: interactive autologin serial shell when `/run/agent-job/job.json` is absent (`nix run .#agent-vm-sandbox`); automated oneshot (`agent-job-runner.sh`) with `SuccessAction = "poweroff"` and `FailureAction = "poweroff"` when present.
   - Read-only host `/nix/store` (`virtiofs` via `virtiofsd`) + `tmpfs` `writableStoreOverlay = "/nix/.rw-store"`, plus `tmpfs` `/tmp` and `/var/tmp`.
   - Swappable `agentBackend` (`claude-code`, `opencode`, `aider`, `custom`) decoupled from the guest base image.
2. **Host Control Plane ([agent-dispatcher.nix](../../modules/services/agent-dispatcher.nix)):**
   - `mint-github-app-token.sh` signs a 9-minute RS256 JWT on the host using `sops-nix`-decrypted `githubPrivateKeyFile` and exchanges it for a 1-hour, single-repository token (`contents: write`, `pull_requests: write`, `issues: write`; `workflows` explicitly omitted).
   - `agent-dispatch-once.sh` serializes runs with `flock`, boots the VM as unprivileged user `agent-vm` inside a `systemd-run` scope (`MemoryMax`, `CPUQuota`, `RuntimeMaxSec`), and wipes `/run/agent-dispatcher/current-job` on exit.
3. **Zero-Trust Egress ([isolation.nft](../../modules/services/agent-dispatcher/isolation.nft)):**
   - Dedicated `inet agent-isolation` nftables table on `br-agent` (`10.240.0.1/24` ↔ `tap-agent0` `10.240.0.2/24`).
   - Drops all `input` from `br-agent` to the host, drops IPv6 and all private/link-local/CGNAT IPv4 ranges in `forward`, and only allows + masquerades public DNS (`1.1.1.1`, `9.9.9.9`) and TCP `22, 80, 443` + UDP `123`.
   - `agent-dispatch-once` fails closed if `inet agent-isolation` is not loaded.

### Consequences

* **Positive:** Untrusted agent runs cannot reach `*.homelab.lan`, ZFS pools, or host secrets, and leave zero `/persist` state.
* **Negative / Trade-off:** `virtiofsd` introduces a larger host-side attack surface than `firecracker`'s `erofs` block device; acceptable for a single-tenant homelab, and switching to `firecracker` remains a localized change in `agent-worker.nix`.
* **Manual Prerequisite:** Requires creating a GitHub App (without `workflows` permission) and adding `agent_dispatcher/github_app_private_key` and `agent_dispatcher/llm_api_key` to `secrets/homelab.yaml`.
