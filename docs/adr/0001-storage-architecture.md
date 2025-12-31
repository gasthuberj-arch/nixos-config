---
status: "accepted"
date: 2025-12-21
decision-makers: Johannes Gasthuber
consulted: N/A
informed: Future administrators, documentation readers
---

# Storage Architecture for 5-Drive Homelab Server

## Context and Problem Statement

We are setting up a NixOS homelab server with 5 physical drives (2x 1TB NVMe, 3x 4TB SATA). The server will host mixed workloads including media storage (pictures), smart home services (Home Assistant), monitoring (Grafana/Prometheus), and download services (torrent client).

How should we architect the storage to balance performance, redundancy, power efficiency, and capacity while supporting both hot (frequently accessed) and cold (archival) data?

## Decision Drivers

* **Data protection**: Personal data (pictures, documents) is important and requires redundancy to prevent loss
* **Power efficiency**: SATA drives should remain spun down when not in use to save power and reduce noise
* **Performance for active services**: Applications like Home Assistant, Prometheus, and active torrents need responsive storage
* **Tiering capability**: Most data will be cold storage; need clear separation between hot and cold tiers
* **Future expandability**: System has capacity for 4 additional NVMe and 6 additional SATA drives
* **External backup strategy**: Restic backups will be implemented as additional protection layer
* **Operational simplicity**: Configuration should be maintainable and well-documented for future reference

## Considered Options

* **Option 1**: Two-tier ZFS architecture (mirrored NVMe hot tier + RAIDZ1 SATA cold tier)
* **Option 2**: Single ZFS pool with all drives (mixed speed pool)
* **Option 3**: Independent filesystems (ext4 on each drive with software RAID)
* **Option 4**: Striped NVMe + SATA RAID (maximize NVMe space, accept single point of failure)

## Decision Outcome

Chosen option: **Option 1 - Two-tier ZFS architecture**, because it best addresses all decision drivers by providing redundancy where needed, clear hot/cold separation for power management, excellent data integrity features, and flexibility for future expansion.

### Storage Layout

**Hot Tier (NVMe):**
- 2x 1TB NVMe drives in ZFS mirror (RAID1 equivalent)
- Usable capacity: ~1TB
- Use cases: OS, application data, databases (Home Assistant, Prometheus), active downloads, cache

**Cold Tier (SATA):**
- 3x 4TB SATA drives in RAIDZ1 (RAID5 equivalent)
- Usable capacity: ~8TB (2 drives worth of data + 1 drive parity)
- Use cases: Picture archives, completed media, long-term backups, inactive data

**Data Migration:**
- Semi-automated tiering using cron jobs to identify and migrate cold data from NVMe to SATA
- Selective folders can remain pinned to NVMe tier as needed

### Consequences

**Good:**
* **Redundancy on both tiers**: Can survive 1 drive failure on NVMe (mirror) and 1 drive failure on SATA (RAIDZ1)
* **Performance where it matters**: NVMe mirror provides low-latency access for active services
* **Power efficiency achieved**: SATA pool can be configured with aggressive spindown, only accessed for archival operations
* **ZFS data integrity**: Checksumming protects against silent data corruption, critical for long-term picture storage
* **Snapshot capability**: ZFS snapshots enable point-in-time recovery and efficient backups
* **Clear operational model**: Hot/cold tiers make data placement decisions obvious
* **Expansion path**: Can add drives to existing pools or create new pools as needs grow

**Bad:**
* **Complexity**: ZFS has a steeper learning curve than ext4/mdadm
* **RAM usage**: ZFS benefits from adequate RAM for ARC cache (recommend 8GB+ for this config)
* **NVMe capacity trade-off**: Mirroring reduces 2TB raw to 1TB usable (but provides critical redundancy)
* **RAIDZ expansion limitations**: Cannot easily add single drives to RAIDZ1 pool (must add in groups or migrate data)

### Confirmation

* ZFS pools are created with the specified topology (1x mirrored vdev for NVMe, 1x RAIDZ1 vdev for SATA)
* Verification: `zpool status` shows correct vdev configuration
* SATA spindown tested: Drives successfully spin down after idle period and wake on access
* Data migration script implemented and tested for moving cold data to SATA tier
* Restic backup successfully configured to backup both tiers to external storage

## Pros and Cons of the Options

### Option 1: Two-tier ZFS architecture (CHOSEN)

* Good, because provides redundancy on both tiers appropriate to data criticality
* Good, because ZFS offers superior data integrity through checksumming and scrubbing
* Good, because clear hot/cold separation enables power-efficient SATA spindown
* Good, because snapshots and send/receive enable efficient backup workflows
* Good, because proven technology with strong NixOS integration
* Neutral, because requires more RAM than simpler filesystems (but acceptable for server)
* Bad, because ZFS has complexity and learning curve for administration
* Bad, because RAIDZ1 expansion requires careful planning (cannot easily add single drives)

### Option 2: Single ZFS pool with all drives

* Good, because single namespace simplifies file management
* Good, because ZFS can automatically tier data (with cache/log devices)
* Bad, because mixing NVMe and SATA in one pool complicates performance characteristics
* Bad, because all drives must spin up together, defeating power efficiency goals
* Bad, because single pool topology is harder to expand incrementally

### Option 3: Independent filesystems (ext4 + mdadm RAID)

* Good, because ext4 is very mature and simple to understand
* Good, because mdadm is well-documented and widely supported
* Good, because lower RAM requirements
* Bad, because no built-in checksumming for data integrity verification
* Bad, because snapshot capabilities are limited (would need LVM layer)
* Bad, because managing multiple independent RAID arrays increases operational complexity
* Bad, because tiering would require manual scripting without filesystem-level support

### Option 4: Striped NVMe + SATA RAID

* Good, because maximizes NVMe usable capacity (2TB instead of 1TB)
* Good, because striping provides higher performance for NVMe tier
* Bad, because single NVMe failure destroys entire hot tier (unacceptable for important data)
* Bad, because relies solely on SATA backups and restic for protection
* Bad, because recovery from NVMe failure requires full restore operation

## More Information

**ZFS Pool Names:**
- Hot tier: `nvme-pool` or `tank-fast`
- Cold tier: `sata-pool` or `tank-archive`

**Recommended ZFS Settings:**
- Enable compression (lz4) for space savings with minimal CPU overhead
- Set appropriate recordsize for different datasets (128K for media, 16K for databases)
- Configure periodic scrubs (monthly) to verify data integrity
- Set SATA pool spindown via `/sys/block/sd*/queue/spindown_time` or hdparm

**Migration Strategy:**
- Implement script to identify files not accessed in 90+ days on NVMe tier
- Candidate files logged for review before automated migration
- Symlinks or bind mounts can maintain application compatibility during migration

**Future Expansion Scenarios:**
- Add 2 more NVMe: Expand mirror to 4-way or create second mirrored pair
- Add 3+ more SATA: Create second RAIDZ1 vdev or migrate to RAIDZ2 for higher redundancy

**Related Decisions:**
- Filesystem choice (ZFS) enables this architecture and will be documented in ADR-0002
- Backup strategy with restic complements this redundancy (future ADR)