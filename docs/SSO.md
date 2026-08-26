# Single Sign-On (SSO) with Authelia

This document describes the SSO implementation for the homelab services using Authelia as the identity provider.

## Overview

Authelia provides centralized authentication for all homelab services using:
- **OIDC (OpenID Connect)** for services with native support (Grafana, Nextcloud, Immich, Paperless)
- **Forward Authentication** for services without OIDC support (proxied through Caddy)
- **TOTP 2FA** support for enhanced security
- **File-based user management** (no external database required)

## Architecture

```
User → Caddy (Reverse Proxy) → Service
         ↓
    Authelia (SSO)
         ↓
    users.yml (User Database)
```

### Services Integration Status

| Service | Integration Method | Status | Notes |
|---------|-------------------|--------|-------|
| Grafana | OIDC | ✅ Full | Native OIDC support |
| Nextcloud | OIDC | ✅ Full | Via oidc_login app |
| Immich | OIDC | ✅ Full | Native OAuth support |
| Paperless | OIDC | ✅ Full | Via django-allauth |
| Home Assistant | Forward Auth | ⚠️ Partial | Requires manual config |

## Default Credentials

**Initial Setup:**
- **Authelia Portal:** https://auth.homelab.lan
- **Username:** `admin`
- **Password:** `changeme` (MUST change on first login)

**Important:** Change the default password immediately after first deployment!

## Configuration

### Enabling SSO

SSO is enabled in your configuration:

```nix
services.authelia-custom = {
  enable = true;
  domain = "homelab.lan";
};
```

### User Management

Users are stored in `/var/lib/authelia-main/users.yml` (or a custom location if specified).

#### Default User File Format

```yaml
users:
  admin:
    displayname: "Administrator"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # Hashed password
    email: admin@homelab.lan
    groups:
      - admins
```

#### Adding New Users

1. **Generate a password hash:**

```bash
# Generate password hash (authelia is already installed when SSO is enabled)
authelia crypto hash generate argon2 --password 'your-password-here'
```

2. **Edit the users file:**

```bash
sudo nano /var/lib/authelia-main/users.yml
```

3. **Add the new user:**

```yaml
users:
  admin:
    displayname: "Administrator"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: admin@homelab.lan
    groups:
      - admins

  john:
    displayname: "John Doe"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: john@homelab.lan
    groups:
      - users
```

4. **Restart Authelia:**

```bash
sudo systemctl restart authelia-main.service
```

### Two-Factor Authentication (2FA)

#### Enabling TOTP for a User

1. Log in to https://auth.homelab.lan
2. Click on your profile (top right)
3. Navigate to "Two-Factor Authentication"
4. Click "Register device"
5. Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)
6. Enter the verification code

#### Enforcing 2FA for All Users

Edit the Authelia configuration:

```nix
services.authelia-custom = {
  enable = true;
  domain = "homelab.lan";
};
```

Then modify `/nix/store/.../authelia.nix` to change:
```nix
policy = "one_factor";  # Change to "two_factor"
```

Or create a custom access control rule.

## Service-Specific Configuration

### Grafana

Grafana uses native OIDC integration. Users are automatically created on first login.

**Admin Role Assignment:**
- Users in the `admins` group → Grafana Admin
- All other users → Grafana Viewer

### Nextcloud

Nextcloud uses the `oidc_login` app for SSO.

**First Time Setup:**
1. Access Nextcloud via https://nextcloud.homelab.lan
2. Click "Log in with Authelia"
3. Authenticate with Authelia credentials
4. User account will be created automatically

**Note:** Local Nextcloud login is still available as a fallback.

### Immich

Immich supports OAuth/OIDC natively.

**Configuration:**
- Auto-registration is enabled
- Users can log in with "Login with Authelia" button
- Mobile app users: Use the web OAuth flow

### Paperless

Paperless uses Django's `allauth` for OIDC support.

**Access:**
- Navigate to https://paperless.homelab.lan
- Click "Sign in with Authelia"
- Authenticate and auto-register

### Home Assistant

Home Assistant requires manual configuration for trusted authentication.

**Setup Steps:**

1. Edit Home Assistant's `configuration.yaml`:

```yaml
homeassistant:
  auth_providers:
    - type: trusted_networks
      trusted_networks:
        - 127.0.0.1
        - ::1
      allow_bypass_login: true
    - type: homeassistant
```

2. Restart Home Assistant

**Note:** Forward auth headers are passed, but Home Assistant manages its own user sessions.

## Secrets Management

Authelia requires several secrets for operation. These are automatically generated on first run:

### Secret Locations

- `/persist/secrets/authelia/jwt-secret` - JWT signing key
- `/persist/secrets/authelia/storage-encryption-key` - Database encryption
- `/persist/secrets/authelia/session-secret` - Session encryption
- `/persist/secrets/authelia/oidc-hmac-secret` - OIDC token signing
- `/persist/secrets/authelia/oidc-issuer-key.pem` - OIDC RSA private key

### Regenerating Secrets

If you need to regenerate secrets (will invalidate all sessions):

```bash
sudo rm /persist/secrets/authelia/*
sudo systemctl restart authelia-generate-secrets.service
sudo systemctl restart authelia-main.service
```

### OIDC Client Secrets

All services currently use the default client secret `insecure_secret`. For production:

1. Generate a strong secret:
```bash
openssl rand -base64 32
```

2. Hash it with Authelia:
```bash
authelia crypto hash generate pbkdf2 --password 'your-secret-here'
```

3. Update the OIDC client configuration in `authelia.nix`
4. Update the corresponding service configuration files

## Access Control

### Default Policy

- **Authelia portal:** Publicly accessible (bypass)
- **All other services:** Require authentication (one_factor)

### Custom Policies

To create more granular access control, edit the access control rules:

```nix
access_control = {
  default_policy = "deny";
  
  rules = [
    {
      domain = [ "auth.${cfg.domain}" ];
      policy = "bypass";
    }
    {
      domain = [ "grafana.${cfg.domain}" ];
      policy = "two_factor";  # Require 2FA
      subject = [ "group:admins" ];  # Only admins
    }
    {
      domain = [ "*.${cfg.domain}" ];
      policy = "one_factor";  # All authenticated users
    }
  ];
};
```

## Troubleshooting

### Cannot Log In to Authelia

1. **Check Authelia service status:**
```bash
sudo systemctl status authelia-main.service
journalctl -u authelia-main.service -n 50
```

2. **Verify users file:**
```bash
sudo cat /var/lib/authelia-main/users.yml
```

3. **Check secrets exist:**
```bash
ls -la /persist/secrets/authelia/
```

### Service Not Redirecting to Authelia

1. **Check Caddy configuration:**
```bash
sudo systemctl status caddy.service
journalctl -u caddy.service -n 50
```

2. **Verify forward auth is configured:**
```bash
curl -I https://immich.homelab.lan
# Should redirect to auth.homelab.lan if not authenticated
```

3. **Check DNS resolution:**
```bash
ping auth.homelab.lan
```

### OIDC Authentication Fails

1. **Check service logs:**
```bash
# For Grafana
journalctl -u grafana.service -n 50

# For Nextcloud
journalctl -u phpfpm-nextcloud.service -n 50
```

2. **Verify OIDC endpoints are accessible:**
```bash
curl http://127.0.0.1:9091/.well-known/openid-configuration
```

3. **Check client ID and secret match:**
- Authelia client configuration
- Service OIDC configuration

### Sessions Expire Too Quickly

Edit session configuration:

```nix
session = {
  expiration = "12h";      # Increase to 24h or more
  inactivity = "1h";       # Increase to 4h or more
  remember_me_duration = "1M";
};
```

### Password Reset Not Working

Authelia uses file-based notifications by default:

```bash
# Check notification file
sudo cat /var/lib/authelia-main/notifications.txt
```

For email notifications, configure an SMTP server in the Authelia settings.

## Security Considerations

### Production Hardening

1. **Change all default passwords immediately**
2. **Enable 2FA for all admin accounts**
3. **Use strong, unique client secrets for OIDC**
4. **Restrict access to secrets directory:**
```bash
sudo chmod 700 /persist/secrets/authelia
sudo chown -R authelia-main:authelia-main /persist/secrets/authelia
```

5. **Enable HTTPS with valid certificates** (configure Let's Encrypt in Caddy)
6. **Review access control policies regularly**
7. **Monitor Authelia logs for suspicious activity**

### Backup Important Files

Regular backups of:
- `/var/lib/authelia-main/users.yml` - User database
- `/var/lib/authelia-main/db.sqlite3` - Session/2FA data
- `/persist/secrets/authelia/` - All secrets

## Advanced Configuration

### LDAP Backend (Alternative to File)

To use LDAP instead of file-based users:

```nix
authentication_backend = {
  ldap = {
    url = "ldap://ldap.homelab.lan";
    base_dn = "dc=homelab,dc=lan";
    user = "cn=admin,dc=homelab,dc=lan";
    password = "ldap-password";
    users_filter = "(&(objectClass=person)(uid={input}))";
    groups_filter = "(member={dn})";
  };
};
```

### Custom Branding

Modify Authelia theme and logo (requires custom package):

1. Create custom assets
2. Mount them in the Authelia configuration
3. Set theme colors in settings

### Integration with External Services

To add additional OIDC clients:

```nix
{
  id = "new-service";
  description = "New Service";
  secret = "$pbkdf2-sha512$...";
  public = false;
  authorization_policy = "one_factor";
  redirect_uris = [
    "https://new-service.homelab.lan/callback"
  ];
  scopes = ["openid" "profile" "email"];
}
```

## References

- [Authelia Documentation](https://www.authelia.com/)
- [OIDC Specification](https://openid.net/connect/)
- [Caddy Forward Auth](https://caddyserver.com/docs/caddyfile/directives/forward_auth)
- [NixOS Authelia Module](https://search.nixos.org/options?query=services.authelia)

## Support

For issues specific to this implementation, check:
1. Service logs: `journalctl -u <service-name>`
2. Authelia logs: `journalctl -u authelia-main.service`
3. Caddy logs: `journalctl -u caddy.service`
4. Configuration files in `/nix/store/` (read-only)