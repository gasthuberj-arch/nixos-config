---
status: "accepted"
date: 2025-12-21
decision-makers: Johannes Gasthuber
consulted: NixOS community best practices, notthebee/nix-config reference
informed: Future administrators, documentation readers
---

# Use Nix Flakes for Configuration Management

## Context and Problem Statement

We are setting up a new NixOS server from scratch. NixOS supports two primary configuration approaches: traditional channel-based configuration and the newer Flakes-based system.

How should we structure our NixOS configuration to ensure reproducibility, maintainability, and alignment with modern best practices?

## Decision Drivers

* **Reproducibility**: Configuration should produce identical results across time and different machines
* **Dependency pinning**: Exact versions of nixpkgs and other inputs should be locked and versioned
* **Modern tooling**: Alignment with current NixOS ecosystem direction and community practices
* **Multi-host management**: Potential future expansion to manage multiple machines from single repository
* **Learning investment**: Time spent learning should apply to current and future NixOS usage
* **Integration with ecosystem**: Compatibility with modern NixOS modules and tools (disko, sops-nix, home-manager, etc.)
* **Git-based workflow**: Configuration should integrate naturally with version control

## Considered Options

* **Option 1**: Nix Flakes with locked inputs
* **Option 2**: Traditional channels with pinned nixpkgs
* **Option 3**: Hybrid approach (channels with flake wrapper)

## Decision Outcome

Chosen option: **Option 1 - Nix Flakes with locked inputs**, because it provides superior reproducibility through automatic dependency locking, has become the de facto standard for modern NixOS configurations, and integrates seamlessly with the ecosystem tools we plan to use (disko, sops-nix).

### Implementation Details

**Structure:**
```
nixos-config/
├── flake.nix           # Main entry point with inputs/outputs
├── flake.lock          # Locked dependency versions (auto-generated)
├── hosts/              # Per-host configurations
│   └── server/
│       ├── configuration.nix
│       └── hardware-configuration.nix
├── modules/            # Reusable configuration modules
└── docs/adr/           # Architecture Decision Records
```

**Key Inputs:**
- `nixpkgs` (24.05 stable channel)
- `nixpkgs-unstable` (for newer packages when needed)
- `disko` (declarative disk partitioning)
- `sops-nix` (secrets management)

**Deployment Pattern:**
```bash
nixos-rebuild switch --flake .#hostname
```

### Consequences

**Good:**
* **Hermetic builds**: `flake.lock` ensures exact same nixpkgs version is used across rebuilds and machines
* **Explicit dependencies**: All external inputs (nixpkgs, modules) declared in one place
* **No channel management**: Eliminates `nix-channel` commands and implicit state
* **Easy rollback**: Git history + flake.lock provides complete configuration history
* **Multi-host ready**: Single repository can manage multiple machines with shared modules
* **Ecosystem alignment**: Modern NixOS tools (disko, agenix, home-manager) expect flakes
* **Upstream direction**: Flakes are stabilizing and becoming the recommended approach
* **Remote builds**: Can build/deploy from any machine with Git access

**Bad:**
* **Still experimental**: Flakes are not yet formally stable (though widely used)
* **Learning curve**: Requires understanding flake schema and Nix language more deeply
* **Breaking changes possible**: Flake specification could change before stabilization
* **Command syntax**: Requires `--experimental-features` flag unless globally enabled

**Neutral:**
* **Opinionated structure**: Flakes enforce specific repository layout (can be good or bad)
* **Build-time evaluation**: All inputs resolved at build time (different from channel model)

### Confirmation

* `flake.nix` exists with proper inputs and outputs structure
* `flake.lock` is committed to Git and contains pinned versions
* `nixos-rebuild switch --flake .#server` successfully builds and activates system
* No `nix-channel` commands required for system management
* `nix flake update` command successfully updates dependencies when desired

## Pros and Cons of the Options

### Option 1: Nix Flakes with locked inputs (CHOSEN)

* Good, because `flake.lock` provides cryptographic hashing of all inputs for true reproducibility
* Good, because single `flake.nix` clearly declares all external dependencies
* Good, because works seamlessly with disko, sops-nix, and other modern NixOS tooling
* Good, because enables trivial multi-host management in future
* Good, because aligns with community direction and modern tutorials/documentation
* Good, because Git integration is first-class (flakes require Git repositories)
* Neutral, because requires learning flake schema and output structure
* Bad, because still technically experimental (though de facto standard)
* Bad, because requires enabling experimental features flag

### Option 2: Traditional channels with pinned nixpkgs

* Good, because officially stable and well-documented for over a decade
* Good, because simpler mental model (no flake schema to learn)
* Good, because no experimental features required
* Bad, because channel management is imperative (stateful) and error-prone
* Bad, because pinning nixpkgs requires manual fetchTarball with explicit hashes
* Bad, because mixing multiple inputs (nixpkgs + other modules) is cumbersome
* Bad, because ecosystem is moving toward flakes (many tools flake-first now)
* Bad, because multi-host management requires custom tooling or repeated configuration

### Option 3: Hybrid approach (channels with flake wrapper)

* Good, because provides gradual migration path
* Good, because can use flake tooling while keeping channel infrastructure
* Neutral, because adds compatibility layer complexity
* Bad, because maintains two systems (channels AND flakes) simultaneously
* Bad, because doesn't gain full reproducibility benefits of pure flakes
* Bad, because confusing for future maintainers (mixed paradigms)

## More Information

**Enabling Flakes:**

For system-wide enablement, add to `configuration.nix`:
```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

For one-time usage:
```bash
nix --experimental-features "nix-command flakes" build
```

**Updating Dependencies:**

Update all inputs:
```bash
nix flake update
```

Update specific input:
```bash
nix flake lock --update-input nixpkgs
```

**Reference Configurations:**
- [notthebee/nix-config](https://github.com/notthebee/nix-config) - Comprehensive homelab example
- [NixOS Wiki - Flakes](https://nixos.wiki/wiki/Flakes)
- [Determinate Systems - Zero to Nix Flakes Guide](https://zero-to-nix.com/concepts/flakes)

**Related Decisions:**
- ADR-0001 (Storage Architecture) - Flakes integrate naturally with disko for declarative disk setup
- Future ADR on secrets management will leverage sops-nix flake integration

**Migration Note:**

If this were a migration from existing channel-based system, the process would involve:
1. Create `flake.nix` wrapping existing `configuration.nix`
2. Generate `flake.lock` with `nix flake update`
3. Test with `nixos-rebuild build --flake .#hostname`
4. Switch with `nixos-rebuild switch --flake .#hostname`
5. Remove channel subscriptions with `nix-channel --remove nixos`

Since this is a greenfield installation, we start directly with flakes.