# Per-Host SOPS Secrets

Each host in the fleet has its own SOPS file governed by `.sops.yaml` so compromising an edge node (`rpi5`, `orin-nx`) or workstation (`work-laptop`, `personal-laptop`) cannot decrypt `homelab` credentials.

| Host | Secret File | Host Key Path |
|---|---|---|
| `homelab` | `secrets/homelab.yaml` | `/persist/etc/ssh/ssh_host_ed25519_key` |
| `work-laptop` | `secrets/work-laptop.yaml` | `/etc/ssh/ssh_host_ed25519_key` |
| `personal-laptop` | `secrets/personal-laptop.yaml` | `/etc/ssh/ssh_host_ed25519_key` |
| `rpi5` | `secrets/rpi5.yaml` | `/etc/ssh/ssh_host_ed25519_key` |
| `orin-nx` | `secrets/orin-nx.yaml` | `/etc/ssh/ssh_host_ed25519_key` |

## One-Time Host Key Enrollment

1. Derive the public `age` key on each target host (or use `scripts/setup-secrets.sh --enroll-age-key`):
   ```bash
   # On homelab (impermanent root):
   nix run nixpkgs#ssh-to-age -- -i /persist/etc/ssh/ssh_host_ed25519_key.pub

   # On standard-disk hosts (work-laptop, personal-laptop, rpi5, orin-nx):
   nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub
   ```
2. Update the corresponding `&<host>` anchor (and `&admin` operator key) in `.sops.yaml`.
3. Encrypt / re-key each file using SOPS:
   ```bash
   for f in secrets/*.yaml; do
     nix run nixpkgs#sops -- -e -i "$f"
   done
   # Or after adding keys later:
   for f in secrets/*.yaml; do
     nix run nixpkgs#sops -- updatekeys "$f"
   done
   ```
4. Once all `secrets/<host>.yaml` files are encrypted with valid SOPS metadata, you may optionally remove `validateSopsFiles = false;` from `hosts/<host>/configuration.nix` to enforce strict build-time SOPS file checks.
