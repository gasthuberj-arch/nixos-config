# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the NixOS server configuration.

## What are ADRs?

Architecture Decision Records document significant architectural decisions made during the project, including the context, options considered, and rationale behind each choice.

## Format

We use the [MADR (Markdown Architecture Decision Records)](https://adr.github.io/madr/) format for our ADRs.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [ADR-0001](0001-storage-architecture.md) | Storage Architecture for 5-Drive Homelab Server | Accepted | 2025-12-21 |
| [ADR-0002](0002-use-flakes-for-configuration.md) | Use Nix Flakes for Configuration Management | Proposed | TBD |
| [ADR-0003](0003-filesystem-choice.md) | Filesystem Choice for Data Storage | Superseded by ADR-0001 | TBD |

## Decision Process

1. **Identify** - Recognize when a decision is architecturally significant
2. **Document** - Create an ADR using the template
3. **Review** - Discuss with relevant stakeholders
4. **Decide** - Update status to "Accepted" or "Rejected"
5. **Implement** - Build according to the decision
6. **Revisit** - If circumstances change, create a new ADR that supersedes the old one

## Status Definitions

- **Proposed**: Decision is being considered
- **Accepted**: Decision has been agreed upon and will be implemented
- **Rejected**: Decision was considered but not chosen (with rationale documented)
- **Deprecated**: Decision is being phased out
- **Superseded by ADR-XXXX**: Decision has been replaced by a newer one

## Creating a New ADR

1. Copy `template.md` to a new file with the next number: `XXXX-short-title.md`
2. Fill in the template sections
3. Update this README's index
4. Open for discussion/review
5. Update status when finalized