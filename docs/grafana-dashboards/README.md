# Grafana Dashboards

This directory contains pre-configured Grafana dashboard templates for your NixOS homelab.

## Available Dashboards

### systemd-services.json

A comprehensive dashboard for monitoring systemd services, specifically tailored for your homelab setup.

**Features:**
- Service status gauges for key services (Immich, Home Assistant, Caddy)
- Active vs. failed service counts over time
- Detailed status table for all key services
- Service restart count tracking
- Live service logs integration with Loki
- Failed services alert table

**Monitored Services:**
- Immich
- Home Assistant
- Caddy
- Grafana
- Prometheus
- Loki
- Promtail
- Paperless
- Nextcloud

## Importing Dashboards

### Via Grafana UI

1. Open Grafana: https://grafana.homelab.lan
2. Navigate to **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select the dashboard file from this directory
5. Select **Prometheus** as the data source for Prometheus queries
6. Select **Loki** as the data source for log queries
7. Click **Import**

### Via Command Line

Copy the dashboard file to Grafana's provisioned dashboards directory:

```bash
sudo cp systemd-services.json /var/lib/grafana/dashboards/
sudo chown grafana:grafana /var/lib/grafana/dashboards/systemd-services.json
```

Grafana will automatically detect and load the dashboard on next restart or reload.

## Customizing Dashboards

### Adding More Services

To monitor additional services, edit the dashboard JSON:

1. Find queries like: `{name=~"(immich|home-assistant|caddy).*\\.service"}`
2. Add your service to the list: `{name=~"(immich|home-assistant|caddy|yourservice).*\\.service"}`
3. Save and re-import the dashboard

### Modifying Panels

You can customize panels directly in Grafana:

1. Open the dashboard
2. Click the panel title → **Edit**
3. Modify queries, visualization settings, or thresholds
4. Click **Save dashboard**
5. Export the modified dashboard: **Share** → **Export** → **Save to file**

## Recommended Community Dashboards

In addition to the custom dashboards here, consider importing these popular community dashboards:

| Dashboard | ID | Description |
|-----------|-----|-------------|
| Node Exporter Full | 1860 | Comprehensive system metrics (CPU, memory, disk, network) |
| Systemd Services | 12486 | Alternative systemd monitoring dashboard |
| ZFS | 7845 | ZFS pool and dataset metrics |
| Loki Dashboard | 13639 | Log analysis and visualization |
| Prometheus 2.0 Stats | 3662 | Prometheus internal metrics |

**How to import by ID:**
1. Go to **Dashboards** → **Import**
2. Enter the dashboard ID
3. Click **Load**
4. Select data sources
5. Click **Import**

## Dashboard Organization

Suggested dashboard organization:

- **Home**: Overview dashboard with key metrics
- **System**: Node exporter, ZFS, system resources
- **Services**: Systemd services monitoring (this dashboard)
- **Logs**: Loki log analysis
- **Applications**: Per-application dashboards (Immich, Home Assistant, etc.)

## Alerts

The systemd-services dashboard includes visual indicators for failed services. To set up actual alerts:

1. Edit a panel showing failed services
2. Switch to the **Alert** tab
3. Configure alert conditions (e.g., "When failed service count is above 0")
4. Set up notification channels (email, Slack, Discord, etc.)
5. Save the dashboard

## Troubleshooting

### Dashboard shows "No data"

- Verify Prometheus is scraping metrics: http://localhost:9090/targets
- Check that exporters are running: `systemctl status prometheus-*-exporter`
- Ensure time range is appropriate (try "Last 6 hours")

### Logs panel is empty

- Verify Loki is receiving logs: `curl http://localhost:3100/ready`
- Check Promtail is running: `systemctl status promtail`
- Verify journal logs are being collected: `journalctl -f`

### Services not showing in table

- Services must be running to appear in metrics
- Check service name matches the regex pattern in the query
- Verify systemd exporter is collecting the metrics

## Contributing

Feel free to create additional dashboards for:
- Individual service deep-dives (e.g., Immich performance metrics)
- ZFS-specific monitoring
- Network traffic analysis
- Custom application metrics

Save them in this directory with descriptive names and update this README.

## Resources

- [Grafana Dashboard Documentation](https://grafana.com/docs/grafana/latest/dashboards/)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Dashboard Gallery](https://grafana.com/grafana/dashboards/)