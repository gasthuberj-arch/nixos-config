# Grafana Monitoring Stack Setup Guide

This guide explains the comprehensive monitoring stack configured in your NixOS homelab.

## Overview

The monitoring stack includes:

- **Grafana**: Visualization and dashboarding platform
- **Prometheus**: Metrics collection and time-series database
- **Loki**: Log aggregation system
- **Promtail**: Log collector for Loki
- **Exporters**: Various metric exporters for system monitoring
  - Node Exporter: System metrics (CPU, memory, disk, network)
  - Systemd Exporter: Service and unit metrics
  - ZFS Exporter: ZFS pool and dataset metrics

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Grafana                              │
│                    (Visualization)                           │
│                  https://grafana.homelab.lan                 │
└───────────────────┬─────────────────┬───────────────────────┘
                    │                 │
        ┌───────────▼─────────┐   ┌──▼──────────────┐
        │     Prometheus      │   │      Loki       │
        │   (Metrics DB)      │   │   (Logs DB)     │
        └───────────┬─────────┘   └──▲──────────────┘
                    │                │
        ┌───────────▼────────────────┴──────────┐
        │           Exporters & Promtail        │
        ├───────────────────────────────────────┤
        │  • Node Exporter (System Metrics)     │
        │  • Systemd Exporter (Services)        │
        │  • ZFS Exporter (Storage)             │
        │  • Promtail (Journal Logs)            │
        └───────────────────────────────────────┘
```

## Configuration

The monitoring stack has been added as a comprehensive service module following the same pattern as your other services.

### Files Added/Modified

1. **New Module**: `modules/services/grafana.nix`
   - Grafana with automatic provisioning
   - Prometheus with 1-year retention
   - Loki for log aggregation
   - Promtail for log collection
   - Multiple exporters for metrics

2. **Updated**: `modules/services/caddy.nix`
   - Added reverse proxy for `grafana.homelab.lan`

3. **Updated**: `hosts/homelab/configuration.nix`
   - Imported the Grafana module
   - Enabled full monitoring stack
   - Added hostname to local DNS

## Default Configuration

```nix
services.grafana-custom = {
  enable = true;
  port = 3000;

  # Prometheus metrics collection
  prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "365d";  # Keep metrics for 1 year
  };

  # Loki log aggregation
  loki = {
    enable = true;
    port = 3100;
  };

  # Exporters for system monitoring
  exporters = {
    node = true;      # System metrics (CPU, memory, disk, etc.)
    systemd = true;   # Systemd service metrics
    zfs = true;       # ZFS pool metrics
  };
};
```

## Accessing the Stack

Once deployed, the services will be accessible at:

- **Grafana**: https://grafana.homelab.lan
- **Prometheus** (direct): http://localhost:9090
- **Loki** (direct): http://localhost:3100

### Default Credentials

- **Username**: `admin`
- **Password**: `changeme`

**⚠️ IMPORTANT**: Change the admin password immediately after first login!

## First-Time Setup

1. **Access Grafana**: Navigate to https://grafana.homelab.lan
2. **Login**: Use `admin` / `changeme`
3. **Change Password**: Grafana will prompt you to change the password
4. **Verify Data Sources**:
   - Go to Configuration → Data Sources
   - Both Prometheus and Loki should be pre-configured
   - Test the connections
5. **Check Default Dashboards**:
   - Go to Dashboards → Browse
   - The "Systemd Services Monitor" dashboard should be automatically installed
   - If not, wait a few minutes or restart Grafana

## Pre-configured Data Sources

### Prometheus
- **URL**: http://127.0.0.1:9090
- **Scrape Interval**: 15 seconds
- **Metrics Available**:
  - System metrics (CPU, memory, disk, network)
  - Systemd service states and metrics
  - ZFS pool health and capacity
  - Prometheus itself

### Loki
- **URL**: http://127.0.0.1:3100
- **Logs Available**:
  - All systemd journal logs
  - Caddy access and error logs
  - Filterable by service, hostname, priority

## Metrics Collected

### Node Exporter (System Metrics)
- **CPU**: Usage, load average, context switches
- **Memory**: Used, free, cached, buffers
- **Disk**: I/O statistics, space usage
- **Network**: Traffic, errors, drops
- **Filesystem**: Mount points, usage
- **Processes**: Running, blocked, sleeping
- **System**: Uptime, boot time

### Systemd Exporter (Service Metrics)
- **Service States**: active, inactive, failed
- **Unit Types**: service, socket, timer, mount
- **Restart Counts**: Track service restarts
- **Start/Stop Times**: Service lifecycle

### ZFS Exporter (Storage Metrics)
- **Pool Health**: Status of rpool and sata-pool
- **Capacity**: Used, available, fragmentation
- **Dataset Metrics**: Individual dataset statistics
- **I/O Statistics**: Read/write operations

## Example Queries

### Prometheus Queries (PromQL)

```promql
# CPU usage percentage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Disk usage percentage
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# ZFS pool usage
zfs_pool_used_bytes / zfs_pool_size_bytes * 100

# Failed systemd services
node_systemd_unit_state{state="failed"}

# Network traffic (bytes/sec)
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# Service restart count
node_systemd_unit_restart_total{name="immich.service"}
```

### Loki Queries (LogQL)

```logql
# All logs from a specific service
{unit="immich.service"}

# Error logs only
{job="systemd-journal"} |= "error"

# Logs from last hour with specific keyword
{job="systemd-journal"} |= "failed" | json

# Caddy access logs
{job="caddy"}

# Count errors per service
sum by (unit) (count_over_time({job="systemd-journal"} |= "error" [1h]))

# Failed systemd units
{unit=~".+\\.service"} |= "Failed"
```

## Creating Dashboards

### Recommended Community Dashboards

Import these pre-built dashboards from https://grafana.com/grafana/dashboards/

1. **Node Exporter Full** (ID: 1860)
   - Comprehensive system metrics
   - CPU, memory, disk, network

2. **Systemd Services** (ID: 12486)
   - Service states and metrics
   - Perfect for monitoring your systemd processes

3. **ZFS** (ID: 7845)
   - ZFS pool and dataset metrics
   - Health and performance monitoring

4. **Loki Dashboard** (ID: 13639)
   - Log analysis and visualization
   - Log volume and patterns

### Importing Dashboards

1. Go to **Dashboards** → **Import**
2. Enter the dashboard ID (e.g., 1860)
3. Select **Prometheus** as the data source
4. Click **Import**

### Creating Custom Dashboards

1. Click **+** → **Dashboard** → **Add new panel**
2. Select data source (Prometheus or Loki)
3. Write your query
4. Choose visualization type
5. Configure panel settings
6. Save dashboard

## Monitoring Your Systemd Services

Since you mentioned using many systemd processes, here's how to monitor them effectively:

### Service State Dashboard

Create a dashboard to monitor your services:

```promql
# All services
node_systemd_unit_state{name=~".+\\.service"}

# Failed services
node_systemd_unit_state{state="failed", name=~".+\\.service"}

# Active services count
count(node_systemd_unit_state{state="active", name=~".+\\.service"})

# Specific service state
node_systemd_unit_state{name="immich.service"}
```

### Service Alerts

Create alerts for service failures:

```promql
# Alert when any service fails
node_systemd_unit_state{state="failed"} > 0

# Alert when specific service is not active
node_systemd_unit_state{name="immich.service", state!="active"} > 0
```

### Service Logs

View logs for specific services in Grafana:

```logql
# All logs from Immich
{unit="immich.service"}

# Errors from all services
{job="systemd-journal"} |= "error" | json

# Logs from specific time range
{unit="home-assistant.service"} | json
```

## Data Persistence

All monitoring data is persisted across reboots:

- **Grafana**: `/var/lib/grafana` (dashboards, settings, users)
- **Prometheus**: `/var/lib/prometheus2` (metrics, retention: 365 days)
- **Loki**: `/var/lib/loki` (logs)
- **Promtail**: `/var/lib/promtail` (log positions)

## Customization

### Adjust Retention Period

Edit `hosts/homelab/configuration.nix`:

```nix
services.grafana-custom = {
  prometheus = {
    retentionTime = "730d";  # 2 years
  };
};
```

### Add More Exporters

The system supports many exporters. To add more:

```nix
# In grafana.nix or configuration.nix
services.prometheus.exporters = {
  # PostgreSQL metrics
  postgres = {
    enable = true;
    dataSourceNames = [
      "user=postgres database=immich sslmode=disable"
    ];
  };

  # NGINX metrics
  nginx = {
    enable = true;
  };
};

# Then add to scrape configs
services.prometheus.scrapeConfigs = [
  {
    job_name = "postgres";
    static_configs = [{
      targets = [ "127.0.0.1:9187" ];
    }];
  }
];
```

### Change Scrape Interval

For higher or lower resolution metrics:

```nix
services.prometheus.globalConfig = {
  scrape_interval = "30s";     # Less frequent scraping
  # or
  scrape_interval = "5s";      # More frequent scraping
};
```

## Troubleshooting

### Check Service Status

```bash
# Grafana
sudo systemctl status grafana.service

# Prometheus
sudo systemctl status prometheus.service

# Loki
sudo systemctl status loki.service

# Promtail
sudo systemctl status promtail.service

# Exporters
sudo systemctl status prometheus-node-exporter.service
sudo systemctl status prometheus-systemd-exporter.service
sudo systemctl status prometheus-zfs-exporter.service
```

### View Logs

```bash
# Grafana logs
sudo journalctl -u grafana -f

# Prometheus logs
sudo journalctl -u prometheus -f

# Loki logs
sudo journalctl -u loki -f

# Promtail logs
sudo journalctl -u promtail -f
```

### Test Exporters

```bash
# Node exporter
curl http://localhost:9100/metrics

# Systemd exporter
curl http://localhost:9558/metrics

# ZFS exporter
curl http://localhost:9134/metrics

# Prometheus targets
curl http://localhost:9090/api/v1/targets
```

### Reset Admin Password

If you forget your password, you can reset it using the Grafana CLI:

```bash
# Reset to a new password
sudo -u grafana grafana-cli admin reset-admin-password newpassword

# Restart Grafana
sudo systemctl restart grafana
```

Alternatively, you can update the password in the configuration:

```nix
# In modules/services/grafana.nix
security = {
  admin_user = "admin";
  admin_password = "yournewpassword";  # Change this
};
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#homelab
```

### Check Prometheus Targets

Navigate to http://localhost:9090/targets to see all scrape targets and their health.

### Loki Not Receiving Logs

```bash
# Check Promtail is running
sudo systemctl status promtail

# Check Promtail configuration
sudo journalctl -u promtail -n 100

# Test Loki API
curl http://localhost:3100/ready
```

## Performance Considerations

### Disk Space

Monitor disk usage for metrics and logs:

```bash
# Prometheus data
du -sh /var/lib/prometheus2/

# Loki data
du -sh /var/lib/loki/

# Grafana data
du -sh /var/lib/grafana/
```

### Memory Usage

The monitoring stack uses approximately:
- **Grafana**: 100-200 MB
- **Prometheus**: 200-500 MB (depends on metrics volume)
- **Loki**: 100-300 MB
- **Promtail**: 50-100 MB
- **Exporters**: 10-50 MB each

Total: ~500-1200 MB depending on configuration and data volume.

## Security Considerations

- Grafana is accessible only via Caddy reverse proxy with TLS
- Prometheus and Loki listen on localhost only
- No external firewall ports opened by default
- Change the default admin password immediately
- Consider enabling Grafana authentication for multiple users
- Review data retention policies for compliance requirements

## Alerting

Grafana supports alerting. To set up alerts:

1. **Configure Alert Channels**: Email, Slack, Discord, etc.
2. **Create Alert Rules**: Define conditions for alerts
3. **Test Alerts**: Ensure notifications work

Example alert rule for high CPU:

```
Query: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
Condition: WHEN avg() OF query(A, 5m, now) IS ABOVE 90
```

## Integration with Home Assistant

You can integrate Grafana metrics into Home Assistant:

1. Install the Prometheus integration in Home Assistant
2. Configure Home Assistant to send metrics to Prometheus
3. Create unified dashboards showing both system and home automation metrics

## Advanced Features

### Remote Monitoring

To access Grafana from outside your LAN:
1. Set up Caddy with Let's Encrypt for a public domain
2. Configure proper authentication
3. Consider using VPN for secure access

### Long-term Storage

For metrics beyond 365 days:
1. Configure Prometheus remote write to a long-term storage backend
2. Options: Thanos, Cortex, VictoriaMetrics, or cloud providers

### High Availability

For production workloads:
1. Run multiple Prometheus instances
2. Use Thanos or Cortex for HA
3. Set up Loki in microservices mode

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL Basics](https://grafana.com/docs/loki/latest/logql/)
- [Dashboard Gallery](https://grafana.com/grafana/dashboards/)
- [NixOS Prometheus Options](https://search.nixos.org/options?query=prometheus)

## Adding More Dashboards

### Automatic Provisioning (Recommended)

The systemd-services dashboard is automatically installed on deployment. To add more custom dashboards:

1. Place dashboard JSON files in `docs/grafana-dashboards/`
2. Update the `grafana-install-dashboards` service in `modules/services/grafana.nix`:

```nix
script = ''
  mkdir -p ${cfg.dataDir}/dashboards
  
  # Copy all dashboard files
  if [ -d ${../../../docs/grafana-dashboards} ]; then
    cp ${../../../docs/grafana-dashboards}/*.json ${cfg.dataDir}/dashboards/ || true
  fi
'';
```

3. Rebuild: `sudo nixos-rebuild switch --flake .#homelab`

### Manual Installation

You can also use the installation script:

```bash
sudo ./scripts/install-grafana-dashboards.sh
```

Or copy dashboards directly:

```bash
sudo cp docs/grafana-dashboards/*.json /var/lib/grafana/dashboards/
sudo chown -R grafana:grafana /var/lib/grafana/dashboards/
sudo systemctl restart grafana
```

### Import via UI

1. Go to Dashboards → Import
2. Upload JSON file or enter dashboard ID
3. Select data sources
4. Click Import

## Next Steps

1. Deploy the configuration
2. Access https://grafana.homelab.lan
3. Change the admin password
4. Verify the systemd dashboard is loaded (Dashboards → Browse)
5. Import recommended community dashboards (IDs: 1860, 12486, 7845)
6. Explore your system metrics
7. Set up alerts for critical service failures
8. Create custom dashboards for your specific workflows
8. Monitor your systemd services and ZFS pools! 📊✨

## Quick Reference

### Access URLs
- Grafana: https://grafana.homelab.lan
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100

### Default Credentials
- Username: `admin`
- Password: `changeme` (CHANGE THIS!)

### Key Directories
- Grafana: `/var/lib/grafana`
- Prometheus: `/var/lib/prometheus2`
- Loki: `/var/lib/loki`
- Promtail: `/var/lib/promtail`

### Useful Commands
```bash
# Check all monitoring services
systemctl status grafana prometheus loki promtail \
  prometheus-node-exporter prometheus-systemd-exporter prometheus-zfs-exporter

# View metrics
curl localhost:9090/api/v1/query?query=up

# View Loki logs
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="systemd-journal"}' | jq
```
