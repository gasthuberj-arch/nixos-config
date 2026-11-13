# Ephemeral MicroVM Isolation & Agent Dispatch Verification

Hands-on verification checklist for `agent-vm-sandbox` and `homelab.services.agentDispatcher` (see [ADR-0005](../docs/adr/0005-ephemeral-microvm-agent-workers.md)).

## Phase 1 — KVM, Process Model & Store Overlay (Workstation or Homelab)

```bash
nix run .#agent-vm-sandbox
```

In a second terminal on the host while the VM is running:
```bash
pid=$(pgrep -f microvm@agent-sandbox)
ls -la /proc/"$pid"/fd | head -n 30
grep -c rw-s /proc/"$pid"/maps
```
- **Observed:** `cloud-hypervisor` runs as an unprivileged user process (`microvm@agent-sandbox`) with guest RAM backed by `mmap` and devices backed by `/dev/kvm`, `eventfd`, and the `virtiofsd` Unix socket.

Inside the guest:
```bash
dmesg | head -n 10
mount | grep -E 'nix/store|ro-store'
overlay-demo
```
- **Observed:** `/nix/.ro-store` is read-only `virtiofs` from the host; `/nix/store` is an `overlay` with its upper layer in `tmpfs` (`/nix/.rw-store`), so derivations built inside the VM never touch the host's `/nix/store`.

## Phase 2 — Memory Blast Radius & Hypervisor Trade-Offs

Inside the guest (2 GB RAM):
```bash
python3 -c 'b=[]; [b.append(bytearray(100<<20)) for _ in iter(int, 1)]'
dmesg | tail -n 15
```
- **Observed:** The guest kernel OOM-kills `python3` inside the VM (`anon-rss` ~1.8 GB); host memory and desktop/server workloads are untouched.

## Phase 3 — Zero-Trust LAN Isolation (On `homelab` after `nixos-rebuild switch`)

Open an interactive shell inside the networked worker VM:
```bash
sudo agent-vm-shell
```

Watch drop counters on the host in another terminal:
```bash
sudo nft list table inet agent-isolation
```

Run inside the guest:
```bash
curl -I https://api.github.com                              # Expected: HTTP 200/301/403 (WAN works)
curl -m 3 -I https://vaultwarden.homelab.lan || echo BLOCKED # Expected: timeout / BLOCKED
ping -c 1 -W 2 192.168.1.1 || echo LAN_BLOCKED               # Expected: 100% packet loss
grep -rn "ghs_" /nix/store/ 2>/dev/null || echo CLEAN        # Run on host: CLEAN
```

## Phase 4 — End-to-End Issue-to-PR Dry Run

After adding the GitHub App secrets to `secrets/homelab.yaml` and uncommenting the `agentDispatcher` options in `hosts/homelab/configuration.nix`:
```bash
sudo agent-dispatch-once --repo gasthuberj-arch/nixos-config --issue 1 --dry-run
```
