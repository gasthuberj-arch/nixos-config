# FUSE, `virtiofs`, and Orb Storage Trade-Offs

Understood that `virtiofs` carries stateful FUSE requests over shared-memory virtqueues to host `virtiofsd`, which explains why ADR-0006 chose ZFS filesystem datasets over ZVOLs (live host inspection/diffing), clean guest poweroff over RAM snapshots (avoiding fragile `DEVICE_STATE` FUSE inode serialization), and pinned UID/GID `2000` across host `agent-vm` and guest `user` under `--sandbox=none`.

## Evidence

Completed [Lesson 0001](../lessons/0001-fuse-virtiofs-and-orb-storage-tradeoffs.html) with 3/3 on retrieval-practice trade-off scenarios after debugging the live UID 975→2000 migration on `homelab`.

## Implications

Can build directly on the guest-host boundary mental model in future lessons (hybrid `vsock`, `tmpfs` overlays over `virtiofs`, and `nftables` egress isolation) without re-explaining FUSE or ZFS dataset vs. ZVOL semantics.
