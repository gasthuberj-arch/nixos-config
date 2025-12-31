# Home Assistant Setup Guide

This guide explains how Home Assistant has been configured in your NixOS homelab.

## Overview

Home Assistant is a popular open-source home automation platform that integrates with thousands of smart home devices and services. It provides a unified interface to control and automate your smart home.

## Configuration

Home Assistant has been added as a service module following the same pattern as your other services (Immich, Paperless, Nextcloud).

### Files Added/Modified

1. **New Module**: `modules/services/homeassistant.nix`
   - Defines the Home Assistant service with configurable options
   - Uses the unstable package for latest features
   - Configures persistence across reboots
   - Sets up reverse proxy integration

2. **Updated**: `modules/services/caddy.nix`
   - Added reverse proxy configuration for `homeassistant.homelab.lan`
   - Updated help messages to include Home Assistant URL

3. **Updated**: `hosts/homelab/configuration.nix`
   - Imported the Home Assistant module
   - Enabled the service with default configuration
   - Added `homeassistant.homelab.lan` to local hostname resolution

## Default Configuration

```nix
services.homeassistant-custom = {
  enable = true;
  port = 8123;
  # dataDir defaults to /var/lib/hass (will be persisted)
};
```

### Options Available

- **enable**: Enable/disable Home Assistant (default: false)
- **port**: Web interface port (default: 8123)
- **dataDir**: Data storage location (default: /var/lib/hass)
- **openFirewall**: Whether to open the firewall port (default: false)

## Accessing Home Assistant

Once deployed, Home Assistant will be accessible at:

- **HTTPS (via Caddy)**: https://homeassistant.homelab.lan
- **Direct HTTP**: http://localhost:8123 (from the server itself)

The service is configured to run behind Caddy's reverse proxy with:
- Internal TLS certificate (self-signed by Caddy's internal CA)
- Trusted proxy headers for proper client IP detection

## First-Time Setup

On first access, Home Assistant will guide you through:

1. **Create User Account**: Set up your admin username and password
2. **Location**: Configure your home location for weather, sunrise/sunset, etc.
3. **Analytics**: Choose whether to share anonymous usage data
4. **Initial Integrations**: Detect and add devices on your network

## Pre-configured Integrations

The following integrations are pre-installed (via `extraComponents`):

### Core
- `default_config`: Essential Home Assistant features
- `met`: Weather data from met.no
- `esphome`: ESP-based DIY devices
- `mqtt`: MQTT broker integration

### Device Integrations
- `homekit`: Apple HomeKit integration
- `homekit_controller`: Control HomeKit devices
- `hue`: Philips Hue lights
- `cast`: Google Cast/Chromecast devices
- `spotify`: Spotify media player
- `plex`: Plex media server

### System Monitoring
- `systemmonitor`: Monitor system resources
- `cpuspeed`: CPU speed monitoring

## Data Persistence

Home Assistant configuration and data are stored in `/var/lib/hass` and persisted across reboots via the impermanence setup. This includes:

- Configuration files (`configuration.yaml`, `automations.yaml`, etc.)
- Database (SQLite by default, tracks device history)
- Custom integrations and components
- User settings and dashboards

## Deployment

To deploy the changes:

```bash
# From the nixos-config directory
sudo nixos-rebuild switch --flake .#homelab
```

Or use the deployment script:

```bash
./deploy.sh
```

## Customization

### Adding More Integrations

Edit `modules/services/homeassistant.nix` and add to the `extraComponents` list:

```nix
extraComponents = [
  # Existing components...
  "zwave_js"     # Z-Wave devices
  "zigbee"       # Zigbee devices
  "sonos"        # Sonos speakers
  # etc.
];
```

### Changing Configuration

For advanced configuration, you can override the `config` attribute in `hosts/homelab/configuration.nix`:

```nix
services.homeassistant-custom = {
  enable = true;
  port = 8123;
};

# Override home-assistant config directly if needed
services.home-assistant.config = {
  # Your custom configuration here
  recorder = {
    db_url = "postgresql://...";  # Use PostgreSQL instead of SQLite
  };
};
```

### External Access

To expose Home Assistant externally (not just on LAN):

1. Set `openFirewall = true` if accessing directly (not recommended)
2. Better: Configure Caddy to use Let's Encrypt and expose via a public domain
3. Consider using Home Assistant Cloud (Nabu Casa) for secure remote access

## Troubleshooting

### Check Service Status

```bash
sudo systemctl status home-assistant.service
```

### View Logs

```bash
sudo journalctl -u home-assistant -f
```

### Access Configuration Files

```bash
cd /var/lib/hass
ls -la
```

### Trust Caddy's Internal CA Certificate

If you want to access Home Assistant via HTTPS without browser warnings:

```bash
# Export the CA certificate
sudo cat /var/lib/caddy/data/caddy/pki/authorities/local/root.crt > homelab-ca.crt

# Import to your system/browser trust store
# (Method varies by OS and browser)
```

## Security Considerations

- Home Assistant is configured to listen on `127.0.0.1` only (not exposed directly)
- Access is proxied through Caddy with TLS
- The firewall is NOT opened by default (set `openFirewall = true` if needed)
- Consider enabling authentication for external access
- Review Home Assistant's security best practices: https://www.home-assistant.io/docs/configuration/securing/

## Additional Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Integrations List](https://www.home-assistant.io/integrations/)
- [Community Forum](https://community.home-assistant.io/)
- [NixOS Home Assistant Options](https://search.nixos.org/options?query=home-assistant)

## Next Steps

1. Deploy the configuration
2. Access https://homeassistant.homelab.lan
3. Complete the onboarding wizard
4. Add your smart home devices
5. Create automations and dashboards
6. Enjoy your smart home! 🏠✨