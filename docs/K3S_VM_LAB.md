# k3s VM Lab: How It Got Built (and What Broke Along the Way)

This documents the path from "add a k3s service" to a working single-node smoke test
and a 3-node HA (embedded-etcd) cluster running in libvirt VMs on `laptop`, plus every
non-obvious problem hit and how it was actually fixed. Read this before touching the
lab again — most of the pain here is NixOS/libvirt-specific and will resurface if
the setup is rebuilt from scratch without these fixes.

---

## 1. Why VMs instead of bare-metal k3s

k3s was first enabled directly on `laptop` (`services.k3s`), with Longhorn for
storage. Longhorn's environment check does this on startup:

```
nsenter --mount=/host/proc/<pid>/ns/mnt --net=/host/proc/<pid>/ns/net iscsiadm --version
```

It hardcodes `/usr/bin/iscsiadm`. NixOS doesn't populate `/usr/bin` (binaries live in
the Nix store, symlinked onto `$PATH` — not into `/usr/bin`), so this failed even
with `services.openiscsi.enable = true` and `iscsiadm` genuinely installed and
working. Fixed once with a `systemd.tmpfiles.rules` symlink
(`L+ /usr/bin/iscsiadm -> ${pkgs.openiscsi}/bin/iscsiadm`), but that just uncovered a
second, unrelated bug: the Longhorn Helm release (pre-existing, installed
2026-09-04) crashed with `default-instance-manager-image ... shouldn't be empty` —
a Helm/chart-level problem, not a NixOS one.

Rather than keep whack-a-moling FHS assumptions on bare metal, we moved k3s+Longhorn
into VMs: a real Ubuntu kernel and real disks make Longhorn behave like it does on
every other distro it's actually tested against. **`services.k3s` and all the
bare-metal Longhorn prereqs (`services.openiscsi`, `iscsi_tcp`/`dm_crypt` kernel
modules, the `nfs-utils` package, the tmpfiles symlink) were removed from
`hosts/laptop/configuration.nix`.**

## 2. Tool choice: quickemu → libvirt

Originally planned as a single disposable VM via `quickemu` (minimal, no daemon).
Quickemu was dropped once "verify multi-master (3-node HA) works" became a
requirement, because:

- Multi-master needs the VMs to reach **each other**, not just the host reaching
  one VM.
- Quickemu's only networking modes are usermode NAT (each VM fully isolated from
  every other VM) or bridging to an existing host bridge.
- Bridging to the physical NIC was checked and ruled out: this laptop's primary
  interface is WiFi (`wlp194s0`); WiFi APs drop frames from MACs they didn't
  authenticate, so VMs bridged to a WiFi NIC silently lose connectivity.

**libvirt** was adopted instead — its default NAT network (`virbr0` +
`192.168.122.0/24` + built-in DHCP) gives every VM a real, mutually-reachable IP
with zero manual bridge/dnsmasq plumbing. `virtualisation.libvirtd.enable = true`
and `programs.virt-manager.enable = true` are now declared in
`hosts/laptop/configuration.nix`; VMs themselves are still created imperatively
via `virt-install` (that's normal for this stack — nobody declares individual
libvirt domains in NixOS options).

## 3. Gotchas hit standing up libvirt (in the order they appeared)

### 3.1 No default NAT network exists on NixOS

`virsh net-list --all` came back completely empty right after enabling libvirtd.
Unlike Debian/Ubuntu packaging, NixOS's libvirtd module doesn't auto-create the
`default` network. Actually irrelevant in the end — see 3.3, this only *looked*
missing because of the session/system split.

### 3.2 `virsh net-start default` → `error creating bridge interface virbr0: Operation not permitted`

The one that ate the most time. Ruled out, in order: AppArmor (inactive, and
`aa-status` isn't even installed), SELinux (not installed), nftables (inactive,
`nft` binary not even present), all systemd sandboxing directives on
`libvirtd.service` (`ProtectSystem`, `ProtectKernelTunables`, `RestrictAddressFamilies`,
capability bounding set — all permissive), network namespaces (identical to the
host shell's), stale/ghost interfaces (none), the `bridge` kernel module (already
loaded — confirmed a plain `sudo ip link add foo type bridge` worked fine), and even
whether *any* systemd-managed process could create a bridge (`systemd-run` test:
yes, fine).

**Actual cause:** running `virsh`/`virt-install` as a normal user with no explicit
connection URI silently targets `qemu:///session` — libvirt's unprivileged,
**per-user** instance, completely separate from the system-wide one, with no
rights to touch host networking. `ps aux` showed `virtnetworkd` running as
`johannes`, not root — that was the tell. The system `libvirtd.service` I'd been
inspecting the whole time was never even being contacted.

**Fix:** always use `qemu:///system` explicitly, or set it as the default:

```nix
# home.nix
home.sessionVariables.LIBVIRT_DEFAULT_URI = "qemu:///system";
```

Once pointed at the system instance, `virsh -c qemu:///system net-list --all`
showed a `default` network **already existed** (NixOS/libvirt ships one), just not
autostarted:

```bash
virsh -c qemu:///system net-start default
virsh -c qemu:///system net-autostart default
```

If you ever see this exact "Operation not permitted" bridge error again: check
`ps aux | grep virtnetworkd` for the process owner before doing anything else.

### 3.3 Missing storage pool and boot directory

`virt-install` failed twice more, each time for a plain missing-directory reason
— NixOS doesn't pre-create any of libvirt's usual scaffolding:

```bash
sudo mkdir -p /var/lib/libvirt/images
virsh -c qemu:///system pool-define-as default dir --target /var/lib/libvirt/images
virsh -c qemu:///system pool-start default
virsh -c qemu:///system pool-autostart default

sudo mkdir -p /var/lib/libvirt/boot   # virt-install wants this for cloud-init staging
```

### 3.4 SSH into a fresh VM: `Permission denied (publickey)` despite a correct key

The guest's `authorized_keys` was verified correct (right key, `600`/`700` perms,
right owner) via the QEMU guest agent. The actual cause: `~/.ssh/id_ed25519` is
passphrase-protected and no `ssh-agent` was running in the shell, so non-interactive
SSH (`BatchMode=yes`) couldn't unlock the key to even attempt auth — not a server-side
problem at all. Worked around it by never touching the passphrase: used
`virsh qemu-agent-command` (guest-exec) to run commands and pull files out of the
VM instead of SSH, for everything in this lab.

### 3.5 Monitor script gave false blanks under zsh

A polling loop used a local variable named `status` — reserved/special in zsh
(`$status` mirrors `$?`), causing a silent `read-only variable` failure under one
execution path but not another. Renamed to `k3s_st`. Generally: avoid `status`,
`pipestatus`, and other zsh special names as variable names in scripts that might
run under zsh.

## 4. Current cluster layout

| Name | Role | IP (static DHCP reservation) | Spec |
| :--- | :--- | :--- | :--- |
| `k3s-master1` | control-plane, etcd (bootstrap, `--cluster-init`) | `192.168.122.141` | 4 vCPU / 12GB / 40GB |
| `k3s-master2` | control-plane, etcd (joined) | `192.168.122.142` | 4 vCPU / 12GB / 40GB |
| `k3s-master3` | control-plane, etcd (joined) | `192.168.122.143` | 4 vCPU / 12GB / 40GB |

All on Ubuntu 24.04 minimal cloud images, provisioned via `virt-install --import
--cloud-init user-data=...`, backed by a shared read-only base qcow2
(`/var/lib/libvirt/images/k3s-node1-base.qcow2`) with a per-VM qcow2 overlay.
Static IPs come from DHCP host reservations on the `default` network, keyed by a
fixed MAC per VM (`52:54:00:12:34:0{1,2,3}`) — set once via
`virsh net-update default add ip-dhcp-host ...`, so join commands could be
pre-written instead of discovered at runtime. All three masters share one join
token (`K3S_TOKEN`, generated once, not committed anywhere).

A single-node smoke test (`k3s-node1`, plain `k3s server`, no `--cluster-init`)
was run first and torn down cleanly before building the 3-node HA cluster from
scratch — confirming the base VM/cloud-init/k3s pipeline works before adding
clustering on top.

`kubectl` on the host talks to this cluster via the `k3s-vm-ha` context in
`~/.kube/config` (pulled from `k3s-master1`'s `/etc/rancher/k3s/k3s.yaml`, server
address rewritten from `127.0.0.1` to `192.168.122.141`). The existing
`qualitatio-local` (k3d) context was left untouched. **Caveat:** the kubeconfig
only lists master1 as the server — if that specific VM goes down, `kubectl` breaks
even though masters 2/3 are still healthy. Fix later if needed by turning `server:`
into a list of all three IPs.

## 5. Useful commands

```bash
# Always target the system instance explicitly if LIBVIRT_DEFAULT_URI isn't loaded yet
virsh -c qemu:///system list --all

# Run a command inside a VM without SSH (via QEMU guest agent)
virsh -c qemu:///system qemu-agent-command <vm-name> \
  '{"execute":"guest-exec","arguments":{"path":"/bin/bash","arg":["-c","<cmd>"],"capture-output":true}}'
# then, with the returned pid:
virsh -c qemu:///system qemu-agent-command <vm-name> \
  '{"execute":"guest-exec-status","arguments":{"pid":<pid>}}'
# out-data in the response is base64-encoded

# Tear everything down
for n in k3s-master1 k3s-master2 k3s-master3; do
  virsh -c qemu:///system destroy "$n"
  virsh -c qemu:///system undefine "$n" --nvram
  sudo rm -f "/var/lib/libvirt/images/$n.qcow2"
done
```

## 6. Files changed

- `hosts/laptop/configuration.nix` — removed `services.k3s` and bare-metal
  Longhorn prereqs; added `virtualisation.libvirtd.enable`,
  `programs.virt-manager.enable`, `virt-viewer`/`cloud-utils` packages, `johannes`
  added to the `libvirtd` group.
- `hosts/laptop/home.nix` — removed the stale `KUBECONFIG` pointing at the
  bare-metal cluster; added `LIBVIRT_DEFAULT_URI = "qemu:///system"`.
