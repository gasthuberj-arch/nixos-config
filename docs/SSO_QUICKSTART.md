# SSO Quick Start Guide

This guide will get you up and running with SSO in under 5 minutes.

## What You Get

After enabling SSO, you'll have:
- **Single login** for Grafana, Nextcloud, Immich, and Paperless
- **Centralized user management** via Authelia
- **Optional 2FA** for enhanced security
- **Secure authentication** for all homelab services

## Quick Deploy

### 1. Enable SSO (Already Done!)

Your configuration already has SSO enabled:

```nix
# In hosts/homelab/configuration.nix
services.authelia-custom = {
  enable = true;
  domain = "homelab.lan";
};
```

### 2. Rebuild Your System

```bash
cd ~/nixos-config
sudo nixos-rebuild switch --flake .#homelab
```

### 3. First Login

After rebuild completes:

1. **Open Authelia portal:** https://auth.homelab.lan
2. **Login with default credentials:**
   - Username: `admin`
   - Password: `changeme`
3. **IMPORTANT:** Change your password immediately!

### 4. Test SSO

Try accessing your services - they'll now redirect to Authelia:

- https://grafana.homelab.lan - Click "Login with Authelia"
- https://nextcloud.homelab.lan - Click "Log in with Authelia"
- https://immich.homelab.lan - Click "Login with Authelia"
- https://paperless.homelab.lan - Click "Sign in with Authelia"

## Service Access Matrix

| Service | URL | SSO Type | Auto-Create User |
|---------|-----|----------|------------------|
| Authelia Portal | https://auth.homelab.lan | - | - |
| Grafana | https://grafana.homelab.lan | OIDC | ✅ Yes |
| Nextcloud | https://nextcloud.homelab.lan | OIDC | ✅ Yes |
| Immich | https://immich.homelab.lan | OIDC | ✅ Yes |
| Paperless | https://paperless.homelab.lan | OIDC | ✅ Yes |
| Home Assistant | https://homeassistant.homelab.lan | Forward Auth | ⚠️ Manual |

## Common Tasks

### Change Your Password

1. Go to https://auth.homelab.lan
2. Login
3. Click your username (top right)
4. Go to "Settings"
5. Enter old and new password

### Enable 2FA (Recommended)

1. Go to https://auth.homelab.lan
2. Login
3. Click your username (top right)
4. Go to "Two-Factor Authentication"
5. Click "Register device"
6. Scan QR code with Google Authenticator / Authy
7. Enter verification code

### Add a New User

```bash
# 1. Generate password hash
authelia crypto hash generate argon2 --password 'NewUserPassword123'

# 2. Edit users file
sudo nano /var/lib/authelia-main/users.yml

# 3. Add user entry
# users:
#   newuser:
#     displayname: "New User"
#     password: "$argon2id$v=19$..."  # Paste hash from step 1
#     email: newuser@homelab.lan
#     groups:
#       - users

# 4. Restart Authelia
sudo systemctl restart authelia-main.service
```

### Check If SSO Is Working

```bash
# Check Authelia is running
sudo systemctl status authelia-main.service

# Check Authelia logs
journalctl -u authelia-main.service -f

# Test OIDC endpoints
curl http://127.0.0.1:9091/.well-known/openid-configuration
```

## Default Groups

- **admins** - Full administrative access to all services
- **users** - Standard user access

## Troubleshooting

### Can't Access Authelia Portal

```bash
# Check service status
sudo systemctl status authelia-main.service

# Check if port is listening
sudo ss -tlnp | grep 9091

# Check Caddy proxy
sudo systemctl status caddy.service
```

### Service Not Redirecting to SSO

```bash
# Verify Caddy configuration
sudo systemctl restart caddy.service

# Check DNS resolution
ping auth.homelab.lan

# Test with curl
curl -I https://grafana.homelab.lan
```

### Wrong Password / Can't Login

Default credentials are:
- **Username:** `admin`
- **Password:** `changeme`

If you changed it and forgot, you'll need to:

```bash
# Generate new password hash
authelia crypto hash generate argon2 --password 'YourNewPassword'

# Edit users file
sudo nano /var/lib/authelia-main/users.yml

# Replace the password hash for admin user
# Restart Authelia
sudo systemctl restart authelia-main.service
```

### Sessions Keep Expiring

Sessions last 12 hours by default with 1 hour inactivity timeout.

To extend:
```nix
# Edit modules/services/authelia.nix
session = {
  expiration = "24h";      # 24 hours
  inactivity = "4h";       # 4 hours idle
  remember_me_duration = "1M";  # 1 month with "remember me"
};
```

## Security Checklist

After deployment:

- [ ] Change default `admin` password
- [ ] Enable 2FA for admin account
- [ ] Review user list (remove test accounts)
- [ ] Test SSO login for each service
- [ ] Backup `/var/lib/authelia-main/users.yml`
- [ ] Backup `/persist/secrets/authelia/`
- [ ] (Optional) Configure email notifications

## Next Steps

For advanced configuration, see:
- **Full documentation:** `docs/SSO.md`
- **User management:** Adding/removing users, groups, permissions
- **2FA enforcement:** Require 2FA for all users
- **Access policies:** Per-service access control
- **Email notifications:** Password resets via email
- **Custom secrets:** Replace default OIDC client secrets

## Files to Backup

Important files for disaster recovery:

```
/var/lib/authelia-main/users.yml          # User database
/var/lib/authelia-main/db.sqlite3         # 2FA/session data
/persist/secrets/authelia/                # All secrets
```

## Need Help?

1. Check service logs: `journalctl -u authelia-main.service`
2. Review configuration: `/nix/store/.../authelia.nix`
3. See full docs: `docs/SSO.md`
4. Test OIDC: `curl http://127.0.0.1:9091/.well-known/openid-configuration`

---

**You're all set! 🎉**

Your homelab now has enterprise-grade SSO with minimal overhead.