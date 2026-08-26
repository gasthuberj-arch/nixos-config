# Mission: Multi-Device NixOS Architecture & Systems Engineering

## Why
Build and maintain a clean, declarative, multi-device NixOS fleet (x86 homelab server, Raspberry Pi 5s, Nvidia Jetson Orin edge AI nodes) without configuration sprawl, leaky abstractions, or fragile hacks.

## Success looks like
- Confidently structuring reusable modules across diverse storage models (ZFS tmpfs/impermanence vs. standard ext4/NVMe).
- Designing deep NixOS modules with clean option namespaces (`homelab.services.*`) and self-registering contracts (Caddy reverse proxy, Authelia SSO).
- Verifying and testing systems declaratively (cold reboots, rollback verification, point-release lifecycle) without ad-hoc shell workarounds.

## Constraints
- German-engineering rigor: high signal, zero fluff, deterministic and reproducible definitions.
- Single unified Git flake repository for all devices.

## Out of scope
- Imperative package managers (apt, pip, snap) or mutable host administration.
