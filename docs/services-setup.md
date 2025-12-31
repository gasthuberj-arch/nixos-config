# Home Lab Services Setup Guide

This guide covers the setup and configuration of services running on your NixOS home lab.

## Services Overview

### Immich (Photo Management)
- **URL**: https://immich.homelab.lan
- **Port**: 2283
- **Data Location**: `/pictures/immich`
- **Description**: Self-hosted photo and video backup solution with automatic organization and AI-powered features.

### Paperless-ngx (Document Management)
- **URL**: https://paperless.homelab.lan
- **Port**: 28981
- **Data Location**: `/var/lib/paperless` (persisted)
- **Description**: Document management system with OCR, tagging, and full-text search.
- **Features**: 
  - Automatic OCR for scanned documents (English + German)
  - Subdirectories as tags
  - Web interface for browsing and searching

### Nextcloud (Cloud Storage & Collaboration)
- **URL**: https://nextcloud.homelab.lan
- **Port**: 80 (internal, proxied by Caddy)
- **Data Location**: `/var/lib/nextcloud` (persisted)
- **Description**: Self-hosted cloud storage, file sync, and collaboration platform.
- **Features**:
  - File storage and sync
  - Calendar and contacts
  - Document editing
  - Photo gallery
  - Redis caching for performance

## Initial Setup

### 1. Deploy Configuration

```bash
# From your nixos-config directory
./deploy.sh
```

### 2. Paperless-ngx Setup

After deployment, Paperless will be available at https://paperless.homelab.lan

**Default Credentials:**
- Username: `admin`
- Password: `changeme` (unless you set a custom password file)

**Important First Steps:**

1. **Change the admin password:**
   - Log in with default credentials
   - Go to Settings → Users → admin → Change password

2. **Configure document consumption:**
   - Upload documents via web interface, or
   - Copy files to `/var/lib/paperless/consume/` on the server
   - Files in subdirectories will automatically get tagged with the subdirectory name

3. **Recommended configuration:**
   - Set up document types and tags
   - Configure correspondence (people/companies)
   - Set up storage paths for organizing documents

### 3. Nextcloud Setup

After deployment, Nextcloud will be available at https://nextcloud.homelab.lan

**Default Credentials:**
- Username: `admin`
- Password: `changeme` (unless you set a custom password file)

**Important First Steps:**

1. **Change the admin password:**
   - Log in with default credentials
   - Go to Settings → Personal → Security → Change password

2. **Install recommended apps:**
   - Navigate to Apps (top-right menu)
   - Recommended apps:
     - Calendar
     - Contacts
     - Tasks
     - Notes
     - Nextcloud Office (for document editing)
     - Photos (enhanced photo gallery)

3. **Set up desktop/mobile sync:**
   - Download Nextcloud client for your devices
   - Use the server URL: https://nextcloud.homelab.lan
   - Login with your credentials

4. **Performance tuning:**
   - Redis caching is already configured
   - APCu local cache is enabled
   - Consider enabling background jobs via cron (already configured)

### 4. SSL Certificate Trust

All services use Caddy's internal CA for HTTPS. You have two options:

**Option 1: Accept self-signed certificates (quick test)**
```bash
curl -k https://paperless.homelab.lan
curl -k https://nextcloud.homelab.lan
```

**Option 2: Trust Caddy's CA (recommended for regular use)**

1. Export the CA certificate from your server:
```bash
sudo cat /var/lib/caddy/data/caddy/pki/authorities/local/root.crt > caddy-ca.crt
```

2. Import it into your browser/system trust store:
   - **Firefox**: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import
   - **Chrome/Edge**: Settings → Privacy and security → Security → Manage certificates → Authorities → Import
   - **macOS**: Open Keychain Access → File → Import Items → Select certificate → Trust → Always Trust
   - **Linux**: Copy to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates`

## Custom Configuration

### Setting Custom Passwords

To set custom passwords for services:

1. **Create password files** (on the server):
```bash
# Paperless password
echo "your-secure-password" | sudo tee /persist/secrets/paperless-admin-pass

# Nextcloud password
echo "your-secure-password" | sudo tee /persist/secrets/nextcloud-admin-pass

# Set appropriate permissions
sudo chmod 600 /persist/secrets/*-admin-pass
```

2. **Update configuration** in `hosts/homelab/configuration.nix`:
```nix
services.paperless-custom = {
  enable = true;
  port = 28981;
  passwordFile = "/persist/secrets/paperless-admin-pass";
};

services.nextcloud-custom = {
  enable = true;
  hostName = "nextcloud.homelab.lan";
  maxUploadSize = "16G";
  adminPasswordFile = "/persist/secrets/nextcloud-admin-pass";
};
```

3. **Redeploy**:
```bash
./deploy.sh
```

### Adjusting Upload Limits

To change Nextcloud's max upload size, modify the configuration:

```nix
services.nextcloud-custom = {
  enable = true;
  maxUploadSize = "32G";  # Change to desired size
};
```

### Changing Data Locations

You can customize where each service stores its data:

```nix
# Example: Store Paperless documents on the /archive pool
services.paperless-custom = {
  enable = true;
  dataDir = "/archive/paperless";
  mediaDir = "/archive/paperless/media";
  consumeDir = "/archive/paperless/consume";
};

# Example: Store Nextcloud data on the /media pool
services.nextcloud-custom = {
  enable = true;
  dataDir = "/media/nextcloud";
};
```

**Important**: If you change data directories, make sure to:
1. Update the persistence configuration to match
2. Ensure the ZFS dataset has enough space
3. Migrate existing data if needed

## Backup Recommendations

### Paperless-ngx
- **Database**: `/var/lib/paperless/db.sqlite3`
- **Documents**: `/var/lib/paperless/media/documents/`
- **Backup method**: Use Paperless's built-in export feature or rsync the data directory

### Nextcloud
- **Database**: PostgreSQL data in `/var/lib/postgresql/`
- **Files**: `/var/lib/nextcloud/data/`
- **Backup method**: Use `nextcloud-occ maintenance:mode --on` before backup, then rsync or use Nextcloud's backup app

### Recommended backup script location
```bash
# Store backups in the /backups pool
/backups/paperless/
/backups/nextcloud/
```

## Troubleshooting

### Service won't start

Check service status:
```bash
sudo systemctl status paperless-consumer.service
sudo systemctl status paperless-web.service
sudo systemctl status nextcloud-setup.service
sudo systemctl status phpfpm-nextcloud.service
```

View logs:
```bash
sudo journalctl -u paperless-web -f
sudo journalctl -u phpfpm-nextcloud -f
```

### Can't access web interface

1. Check if Caddy is running:
```bash
sudo systemctl status caddy
```

2. Verify hostname resolution:
```bash
ping paperless.homelab.lan
ping nextcloud.homelab.lan
```

3. Test direct port access:
```bash
curl http://localhost:28981  # Paperless
curl http://localhost:80      # Nextcloud (via PHP-FPM)
```

### Paperless not consuming documents

1. Check consume directory permissions:
```bash
ls -la /var/lib/paperless/consume/
```

2. Check consumer service:
```bash
sudo systemctl status paperless-consumer
sudo journalctl -u paperless-consumer -f
```

### Nextcloud showing warnings

1. Run the maintenance check:
```bash
sudo nextcloud-occ status
sudo nextcloud-occ maintenance:repair
```

2. Clear Redis cache:
```bash
sudo systemctl restart redis-nextcloud
```

## Performance Tips

### Paperless-ngx
- Adjust OCR languages if needed (edit `PAPERLESS_OCR_LANGUAGE` in module)
- Enable parallel consumption for faster processing
- Use tags and document types for better organization

### Nextcloud
- Redis and APCu caching are already configured for optimal performance
- Consider enabling preview generation for faster thumbnail loading
- Use the Nextcloud desktop client for efficient sync
- Run background jobs via cron (already configured)

## Additional Resources

- [Paperless-ngx Documentation](https://docs.paperless-ngx.com/)
- [Nextcloud Admin Manual](https://docs.nextcloud.com/server/latest/admin_manual/)
- [Caddy Documentation](https://caddyserver.com/docs/)