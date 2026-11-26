# Multi-Device NixOS Architecture Resources

## Knowledge

- [NixOS Manual: Writing NixOS Modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
  Primary official documentation for `options`, `config`, `mkOption`, `mkIf`, and module evaluation.
- [Misterio77's Nix Starter Configs](https://github.com/Misterio77/nix-starter-configs)
  Standard community reference for multi-host flake layouts, core modules, and host manifests.
- [Elis Hirwing: Erase your darlings (Impermanence with ZFS/tmpfs)](https://grahamc.com/blog/erase-your-darlings/)
  Foundational article on ephemeral root filesystems, ZFS blank snapshots, and `/persist` boundaries.
- [Ousterhout: *A Philosophy of Software Design*](https://web.stanford.edu/~ouster/cgi-bin/book.php)
  Foundational engineering text for deep modules, small interfaces, information hiding, and clean seams.
- [Linux Kernel Docs: virtiofs (Shared File System)](https://docs.kernel.org/filesystems/virtiofs.html)
  Primary reference on how the guest `virtiofs` driver sends FUSE requests over virtqueues to a host daemon instead of `/dev/fuse`. Use for: guest-host storage boundaries and DAX.
- [Linux Kernel Docs: FUSE (Filesystem in Userspace)](https://docs.kernel.org/filesystems/fuse.html)
  Primary specification of FUSE I/O modes, caching, and kernel-to-userspace request forwarding. Use for: understanding stateful FUSE handles and caching trade-offs.
- [virtiofsd: Live Migration & Sandboxing Docs](https://gitlab.com/virtio-fs/virtiofsd/-/blob/main/doc/migration.md)
  Primary design doc explaining why `virtiofsd` tracks guest-opened inodes in memory and why snapshotting/migrating a VM with `virtiofs` requires explicit state transfer (`find-paths` / `file-handles`).
- [OpenZFS Docs: ZFS Concepts (Filesystems vs. ZVOLs)](https://openzfs.github.io/openzfs-docs/man/master/7/zfsconcepts.7.html)
  Primary reference for ZFS filesystem datasets (`recordsize`, POSIX hierarchy) vs. raw block-device volumes (`zvol`, fixed `volblocksize`). Use for: VM storage architecture trade-offs.
- [Linux Manual: `vsock(7)`](https://man7.org/linux/man-pages/man7/vsock.7.html)
  Primary specification of the `AF_VSOCK` address family, Context Identifiers (CIDs), and host-guest stream sockets.
- [systemd Manual: `systemd-ssh-proxy(1)` & `systemd-ssh-generator(8)`](https://www.freedesktop.org/software/systemd/man/latest/systemd-ssh-proxy.html)
  Official documentation for `vsock-mux/` URI routing, `ProxyUseFdpass=yes`, and the `systemd.ssh_auto=no` kernel parameter.
- [Cloud Hypervisor Docs: Hybrid `virtio-vsock`](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/vsock.md)
  Primary spec for Cloud Hypervisor's Unix-socket-backed hybrid vsock and the `CONNECT <port>\n` host-to-guest handshake.
- [Linux Kernel Docs: Universal TUN/TAP Device Driver](https://docs.kernel.org/networking/tuntap.html)
  Primary kernel reference for Layer-2 TAP devices vs. Layer-3 TUN devices and `IFF_MULTI_QUEUE` parallel packet queues.
- [nftables Wiki: Configuring Chains & Hooks](https://wiki.nftables.org/wiki-nftables/index.php/Configuring_chains)
  Official reference on `inet` tables, base chain hooks (`input`, `forward`, `postrouting`), hook priorities, and why a `drop` verdict in any base chain is final.

## Wisdom (Communities)

- [NixOS Discourse](https://discourse.nixos.org/)
  High-signal official community forum for NixOS architectural questions and RFC discussions.
- [NixOS Matrix Channels](https://matrix.to/#/#community:nixos.org)
  Real-time discussions with Nixpkgs maintainers and NixOS power users.
