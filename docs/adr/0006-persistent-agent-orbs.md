---
status: "proposed"
date: 2026-11-25
decision-makers: Johannes Gasthuber
consulted: N/A
informed: Future administrators, documentation readers
---

# Pausable Agent Orbs on Homelab (extends ADR-0005)

## Context and Problem Statement

[ADR-0005](0005-ephemeral-microvm-agent-workers.md) gives one batch worker at a time: issue in, PR out, VM powered off, nothing kept. Interactive agent work needs VMs that live for days, pause without losing the workspace, and run several at once. As of commit 85ca72e the worker cannot do that:

* Root and the `/nix/store` overlay are tmpfs, so nothing survives poweroff (`modules/microvms/agent-worker.nix`).
* TAP `tap-agent0`, IP `10.240.0.2`, MAC `02:00:00:a6:e0:02` and vsock CID 3 are fixed at evaluation time, and `agent-dispatch-once.sh` holds a global `flock`.
* microvm.nix generates the cloud-hypervisor command line at evaluation time; it has no per-instance templating of one guest.

## Decision Drivers

* Single user, homelab only. ADR-0005's virtiofs trust boundary stays accepted.
* Only the workspace must survive a pause; process state may be lost.
* No per-token billing: the agent runs on the existing Antigravity (`agy`) plan.
* A stolen in-VM credential should reach as little as possible.
* Keep the lifecycle contract compatible with Amp's self-hosted orb provider (`spawn`, `pause`, `delete`, idempotent, env-var driven), without adopting Amp now.

## Considered Options

* **Pause mechanism:** poweroff with workspace kept vs. cloud-hypervisor `pause` (RAM held) vs. `snapshot`/`restore`.
* **Workspace storage:** ZFS dataset over virtiofs vs. ZFS zvol over virtio-blk.
* **Concurrency:** K slot variants evaluated at build time vs. a launcher rewriting the CH command line at runtime.
* **Front end:** own CLI vs. Amp orb provider.
* **agy credential:** Gemini API key vs. service-account ADC vs. the owner's OAuth login.

## Decision Outcome

### Lifecycle

* An orb is bound to one repo and branch; its ID derives from the repo name.
* Operations: `spawn`, `pause`, `delete`, each idempotent. `spawn` on a paused orb resumes it.
* **Pause = clean guest poweroff**: the dataset stays, the slot is freed. Resume is a cold boot into any free slot.
  * Rejected: CH `pause` keeps RAM and the slot occupied. CH 53.1 `snapshot` with a vhost-user-fs device silently omits FUSE state unless virtiofsd accepts `DEVICE_STATE` (unverified for virtiofsd 1.13.3).
* Host reboot: orbs come back paused; none auto-start.
* Ephemeral = batch (`orb spawn OWNER/REPO --spec FILE --issue N`): ID `<repo>-i<N>`, wall-clock limit `worker.timeoutSeconds`, not resumable, deleted by `agent-dispatch-once` when its job ends. Interactive orbs have no wall-clock limit.
* GC: `orb gc`, run daily by `orbs-gc.timer` (`Persistent=true`). All decisions under the state-table lock.
  * Expiry: an interactive orb paused more than 14 days (`paused_at`) is renamed to `rpool/orbs-trash/<id>-<epoch>` and its state entry removed. Batch and running orbs never expire.
  * Trash, not a snapshot: destroying a dataset destroys its snapshots. `rpool/orbs-trash` (`mountpoint=none`) is created next to `rpool/orbs`.
  * Trash entries whose `<epoch>` is more than 7 days old are destroyed.
  * Reaper: datasets under `rpool/orbs` with no state entry go to trash the same way (never destroyed directly: may be a crash mid-spawn). Running transient `orb-<id>` units with no state entry are stopped. Slots no running orb holds get their workspace unmounted and `job/`, `vm/` wiped. TAPs are static per slot, so not reaped.
  * If an orphan unit does not stop, gc fails before reaping slots and datasets.
  * Restore within 7 days, by hand: `zfs rename rpool/orbs-trash/<id>-<epoch> rpool/orbs/<id>`. The state entry is gone, so follow with `orb spawn OWNER/REPO [--branch B]`, which reuses the existing dataset. Until then the next gc run trashes it again as an orphan.
  * If `orb spawn OWNER/REPO` ran after expiry, `rpool/orbs/<id>` exists again and the rename collides. The id is derived from the repo name and `orb spawn ID` needs a state entry, so the trash copy cannot run under another id. Instead `orb pause <id>`, `zfs rename rpool/orbs/<id> rpool/orbs-trash/<id>-$(date +%s)` , rename the trash copy back, then `orb spawn <id>`. To drop the new one instead: `orb delete <id>`, rename back, `orb spawn OWNER/REPO`.
  * `orb delete` stays an immediate destroy.

### Compute and addressing

* `homelab.services.orbs.maxConcurrent` slots, default 4 at 4 GB (homelab has 64 GB).
* Each slot is its own `nixosSystem` evaluation (`lib.genAttrs` over slot numbers). Everything derives from slot N: `tap-orb<N>`, IP `10.240.0.(10+N)`, MAC `02:00:00:a6:e0:<N as two hex digits>`, vsock CID `10+N`. The host reads these from the evaluated guest (`agentWorker.derived`).
* State table: `/persist/orbs/state/<id>.json` (outside the impermanence rollback). One `flock` (`/run/orbs/lock`) guards slot allocation and every state-table write.
* `nixos-rebuild switch` reloads `agent-dispatcher-network` instead of restarting it, so running orbs keep their TAPs.

### Storage

* Shared read-only host store over virtiofs plus the tmpfs store overlay, unchanged.
* One ZFS dataset per orb, `rpool/orbs/<id>` with quota 20G, shared over virtiofs as `/home/user`. Chosen over a zvol so the host can read and `git diff` a workspace directly.
* Toolset: the fixed base from `agent-worker.nix` plus `nix develop` on the repo's own flake.

### Access and network

* Guest sshd listens on AF_VSOCK port 22 only. The guest needs kernel param `systemd.ssh_auto=no`, else systemd-ssh-generator binds its own vsock:22 socket.
* `orb attach <id> [-L port]` runs ssh with `ProxyCommand=systemd-ssh-proxy` to host `vsock-mux/run/orbs/slot<N>/vm/notify.vsock` (cloud-hypervisor hybrid vsock) and lands in tmux session `main`. No Caddy portals.
* `isolation.nft` unchanged for every orb. Per-orb allowlist sets keyed by orb IP: not yet implemented.

### Secrets and agent

* GitHub: the host mints a 1-hour token scoped to the orb's repo (`mint-github-app-token.sh`), writes it to the job share as `github_token` at spawn and rewrites it every 30 min (`orbs-token-refresh.timer`). The guest's git credential helper and `gh` wrapper re-read the file on every call. No vsock server.
* agy: the owner's Google OAuth login (plan quota, no per-token cost).
  * Logged in once on the host with the paste-code flow, stored root-only under `/persist/orbs/agy-cred` (agy writes it itself, so sops cannot hold it).
  * Copied into the guest's tmpfs `~/.gemini` per boot; never on the orb dataset or in its snapshots.
  * Only orbs for repos on the owner allowlist (the batch poller's list) receive it.
  * Rejected: Gemini API key with `modelProvider: gemini` and service-account ADC via `AGY_ADC_AUTH` both bill per token.
* New `agentBackend = "antigravity"` (default): `agy -p … --dangerously-skip-permissions`, run as `user` with passwordless sudo. `pkgs/antigravity.nix` patches the binary with autoPatchelfHook; the guest has no nix-ld.
* Batch dispatcher becomes `orb spawn --spec` → `orb wait` → `orb delete`, sharing the slot pool; with no free slot it retries on the next poll. A failed `orb wait` relabels the issue `agent-failed`.

### Consequences

* **Positive:** several resumable orbs with host-inspectable workspaces; the batch path exercises the same lifecycle; an Amp front end can be added later as `amp orb provider` over the same dispatch script.
* **Negative / Trade-off:** every orb holding the agy token carries a Google refresh token with `cloud-platform` scope (scope list from third-party reimplementations, not Google docs). Its reach is bounded by the GCP projects the account has IAM on; possible `drive*` scopes cannot be narrowed on a personal account, only revoked.
* **Negative:** resume is a cold boot (seconds); running processes do not survive pause.
* **Manual prerequisites:**
  * Before the first orb gets the token, confirm the Google account owns no GCP project with billing or real resources (`gcloud projects list`).
  * Revoking the agy grant is part of the incident checklist.
