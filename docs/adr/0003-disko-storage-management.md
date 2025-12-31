---
status: "accepted"
date: 2025-01-19
decision-makers: [Johannes Gasthuber]
---

# Use Disko for Declarative Storage Management

## Context and Problem Statement

How should we manage storage layout and filesystem configuration across multiple NixOS machines in a way that is declarative, reproducible, and maintainable while supporting diverse storage requirements (LUKS encryption, Btrfs with subvolumes, swap, etc.)?

## Decision Drivers

* NixOS configurations should be fully declarative and reproducible
* Storage layout needs to support encryption (LUKS) for security
* Different machines require different filesystem layouts (desktop with Btrfs subvolumes, server with simple ext4)
* Manual partitioning during installation is error-prone and not reproducible
* Storage configuration should be version-controlled alongside other NixOS configuration
* Initial machine setup should be as automated as possible

## Considered Options

* Manual partitioning with NixOS configuration
* Disko for declarative storage management
* Custom partitioning scripts
* NixOps storage management

## Decision Outcome

Chosen option: "Disko for declarative storage management", because it provides a declarative, reproducible way to manage storage layouts that integrates seamlessly with NixOS flakes and supports all required features (LUKS, Btrfs, various filesystem types) while maintaining the configuration as code principle.

### Consequences

* Good, because storage layout is now fully declarative and version-controlled
* Good, because machine provisioning becomes more automated and less error-prone
* Good, because storage configuration can be reviewed and tested like any other code
* Good, because Disko handles complex scenarios like LUKS encryption and Btrfs subvolumes declaratively
* Good, because it's easier to document and understand the storage layout of each machine
* Neutral, because it adds another dependency to the NixOS configuration
* Bad, because there's a learning curve for the Disko configuration syntax
* Bad, because changing storage layout on existing systems requires careful migration planning

### Confirmation

The implementation can be confirmed by:
* Verifying that each host in `hosts/*/disko-config.nix` contains a complete declarative storage configuration
* Successfully provisioning a new machine using only the Disko configuration without manual partitioning
* Validating that the generated filesystems match the declarative specification after installation

## Pros and Cons of the Options

### Manual partitioning with NixOS configuration

Manual partitioning during installation with NixOS configuration only managing mount points and filesystem options.

* Good, because it's the traditional approach with extensive documentation
* Good, because it requires no additional tools or dependencies
* Neutral, because partition layout still needs to be documented somewhere
* Bad, because partitioning steps are not reproducible or version-controlled
* Bad, because it's easy to make mistakes during manual partitioning
* Bad, because rebuilding a machine requires remembering or documenting the partition layout
* Bad, because storage configuration lives outside the declarative configuration system

### Disko for declarative storage management

Use Disko to declaratively define entire storage layouts including partitions, LUKS, filesystems, and mount points.

* Good, because the entire storage stack is declared as code
* Good, because it integrates well with NixOS flakes
* Good, because it supports all required features (LUKS, Btrfs, subvolumes, swap)
* Good, because storage layouts are reproducible across machine rebuilds
* Good, because configuration is version-controlled with the rest of the system
* Good, because it reduces manual steps during installation
* Neutral, because it's a relatively new tool with a growing ecosystem
* Bad, because it adds complexity to the configuration
* Bad, because storage layout changes require careful planning on existing systems

### Custom partitioning scripts

Write custom shell scripts for each machine's partitioning needs.

* Good, because it provides full control over the partitioning process
* Good, because scripts can be version-controlled
* Neutral, because scripts need to be written and maintained
* Bad, because it requires maintaining custom shell scripts
* Bad, because scripts are harder to review and validate than declarative configs
* Bad, because error handling and edge cases need to be manually implemented
* Bad, because it doesn't integrate with the NixOS configuration system

### NixOps storage management

Use NixOps deployment tool which includes storage management capabilities.

* Good, because it provides declarative storage management
* Good, because it's part of the official NixOS ecosystem
* Neutral, because it's primarily designed for deployment orchestration
* Bad, because it's heavier-weight, requiring the full NixOps deployment infrastructure
* Bad, because NixOps is less actively maintained compared to newer tools
* Bad, because it couples storage management with deployment orchestration
* Bad, because it's less suitable for single-machine or mixed-deployment scenarios

## More Information

The decision to use Disko aligns with the broader decision to use Nix flakes (ADR-0002) for configuration management. Disko configurations are stored per-host in `hosts/*/disko-config.nix` files, allowing each machine to have its own storage layout while maintaining consistency in the declarative approach.

Key implementation details:
* Each host has its own `disko-config.nix` defining its specific storage needs
* Disko is integrated into the flake inputs for version pinning
* Installation process uses `disko-install` or similar commands to apply configurations
* Storage layouts support LUKS encryption, Btrfs subvolumes, and various filesystem types as needed per host