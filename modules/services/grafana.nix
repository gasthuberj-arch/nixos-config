{ config, lib, pkgs, pkgs-unstable, ... }:

with lib;

let
  cfg = config.services.grafana-custom;
in
{
  options.services.grafana-custom = {
    enable = mkEnableOption "Grafana monitoring stack with Prometheus and Loki";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/grafana";
      description = "Path to store Grafana data";
    };

    prometheus = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus metrics collection";
      };

      port = mkOption {
        type = types.port;
        default = 9090;
        description = "Port for Prometheus web interface";
      };

      retentionTime = mkOption {
        type = types.str;
        default = "365d";
        description = "How long to retain metrics";
      };
    };

    loki = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Loki log aggregation";
      };

      port = mkOption {
        type = types.port;
        default = 3100;
        description = "Port for Loki";
      };
    };

    exporters = {
      node = mkOption {
        type = types.bool;
        default = true;
        description = "Enable node exporter for system metrics";
      };

      systemd = mkOption {
        type = types.bool;
        default = true;
        description = "Enable systemd exporter for service metrics";
      };

      zfs = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ZFS exporter for ZFS pool metrics";
      };
    };
  };

  config = mkIf cfg.enable {
    # Grafana
    services.grafana = {
      enable = true;
      package = pkgs-unstable.grafana;

      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.port;
          domain = "grafana.${config.services.caddy-custom.domain}";
          root_url = "https://grafana.${config.services.caddy-custom.domain}";
        };

        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };

        security = {
          admin_user = "admin";
          admin_password = "$__file{/persist/secrets/grafana/admin-password}";
        };

        # OIDC authentication via Authelia
        "auth.generic_oauth" = mkIf config.services.authelia-custom.enable {
          enabled = true;
          name = "Authelia";
          client_id = "grafana";
          client_secret = "$__file{/persist/secrets/grafana/oidc-client-secret}";
          scopes = "openid profile email groups";
          auth_url = "https://auth.${config.services.caddy-custom.domain}/api/oidc/authorization";
          token_url = "http://127.0.0.1:${toString config.services.authelia-custom.port}/api/oidc/token";
          api_url = "http://127.0.0.1:${toString config.services.authelia-custom.port}/api/oidc/userinfo";
          login_attribute_path = "email";
          groups_attribute_path = "groups";
          name_attribute_path = "name";
          email_attribute_path = "email";
          use_pkce = true;
          role_attribute_path = "contains(groups[*], 'admins') && 'Admin' || 'Viewer'";
          allow_sign_up = true;
          skip_org_role_sync = false;
          use_refresh_token = true;
        };
      };

      provision = {
        enable = true;

        datasources.settings.datasources = [
          (mkIf cfg.prometheus.enable {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:${toString cfg.prometheus.port}";
            isDefault = true;
            jsonData = {
              timeInterval = "15s";
            };
          })
          (mkIf cfg.loki.enable {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://127.0.0.1:${toString cfg.loki.port}";
          })
        ];

        dashboards.settings.providers = [{
          name = "default";
          options.path = "/var/lib/grafana/dashboards";
        }];
      };
    };

    # Prometheus
    services.prometheus = mkIf cfg.prometheus.enable {
      enable = true;
      port = cfg.prometheus.port;
      retentionTime = cfg.prometheus.retentionTime;

      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };

      scrapeConfigs = [
        # Prometheus itself
        {
          job_name = "prometheus";
          static_configs = [{
            targets = [ "127.0.0.1:${toString cfg.prometheus.port}" ];
          }];
        }

        # Node exporter (system metrics)
        (mkIf cfg.exporters.node {
          job_name = "node";
          static_configs = [{
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        })

        # Systemd exporter
        (mkIf cfg.exporters.systemd {
          job_name = "systemd";
          static_configs = [{
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.systemd.port}" ];
          }];
        })

        # ZFS exporter
        (mkIf cfg.exporters.zfs {
          job_name = "zfs";
          static_configs = [{
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.zfs.port}" ];
          }];
        })
      ];

      # Prometheus exporters
      exporters = {
        node = mkIf cfg.exporters.node {
          enable = true;
          enabledCollectors = [
            "systemd"
            "processes"
            "cpu"
            "diskstats"
            "filesystem"
            "loadavg"
            "meminfo"
            "netdev"
            "stat"
            "time"
            "uname"
          ];
        };

        systemd = mkIf cfg.exporters.systemd {
          enable = true;
        };

        zfs = mkIf cfg.exporters.zfs {
          enable = true;
        };
      };
    };

    # Loki log aggregation
    services.loki = mkIf cfg.loki.enable {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.loki.port;
        auth_enabled = false;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore = {
                store = "inmemory";
              };
              replication_factor = 1;
            };
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 999999;
          chunk_retain_period = "30s";
        };

        schema_config = {
          configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-index";
            cache_location = "/var/lib/loki/tsdb-cache";
          };
          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
          allow_structured_metadata = false;
        };

        table_manager = {
          retention_deletes_enabled = false;
          retention_period = "0s";
        };

        compactor = {
          working_directory = "/var/lib/loki";
          compactor_ring = {
            kvstore = {
              store = "inmemory";
            };
          };
        };
      };
    };

    # Promtail log collector
    services.promtail = mkIf cfg.loki.enable {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };

        positions = {
          filename = "/var/lib/promtail/positions.yaml";
        };

        clients = [{
          url = "http://127.0.0.1:${toString cfg.loki.port}/loki/api/v1/push";
        }];

        scrape_configs = [
          # System journal logs
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };
            relabel_configs = [
              {
                source_labels = [ "__journal__systemd_unit" ];
                target_label = "unit";
              }
              {
                source_labels = [ "__journal__hostname" ];
                target_label = "hostname";
              }
              {
                source_labels = [ "__journal_priority" ];
                target_label = "priority";
              }
            ];
          }

          # Caddy logs
          {
            job_name = "caddy";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "caddy";
                host = config.networking.hostName;
                __path__ = "/var/log/caddy/*.log";
              };
            }];
          }
        ];
      };
    };

    # Create directories for Grafana
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 grafana grafana -"
      "d ${cfg.dataDir}/dashboards 0750 grafana grafana -"
      "d /persist/secrets/grafana 0700 grafana grafana -"
    ];

    # Create Grafana secrets if they don't exist
    systemd.services.grafana-generate-secrets = mkIf config.services.authelia-custom.enable {
      description = "Generate Grafana secrets if they don't exist";
      wantedBy = [ "multi-user.target" ];
      before = [ "grafana.service" ];

      script = ''
        SECRETS_DIR="/persist/secrets/grafana"
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"

        # Generate admin password
        if [ ! -f "$SECRETS_DIR/admin-password" ]; then
          echo "changeme" > "$SECRETS_DIR/admin-password"
          chmod 600 "$SECRETS_DIR/admin-password"
        fi

        # Generate OIDC client secret
        if [ ! -f "$SECRETS_DIR/oidc-client-secret" ]; then
          echo "insecure_secret" > "$SECRETS_DIR/oidc-client-secret"
          chmod 600 "$SECRETS_DIR/oidc-client-secret"
        fi

        chown -R grafana:grafana "$SECRETS_DIR"
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };



    # Persist monitoring data across reboots
    environment.persistence."/persist" = {
      directories = [
        {
          directory = cfg.dataDir;
          user = "grafana";
          group = "grafana";
          mode = "0750";
        }
        (mkIf cfg.prometheus.enable {
          directory = "/var/lib/prometheus2";
          user = "prometheus";
          group = "prometheus";
          mode = "0750";
        })
        (mkIf cfg.loki.enable {
          directory = "/var/lib/loki";
          user = "loki";
          group = "loki";
          mode = "0750";
        })
        (mkIf cfg.loki.enable {
          directory = "/var/lib/promtail";
          user = "promtail";
          group = "promtail";
          mode = "0750";
        })
        {
          directory = "/persist/secrets/grafana";
          user = "grafana";
          group = "grafana";
          mode = "0700";
        }
      ];
    };

    # System packages for debugging
    environment.systemPackages = with pkgs; [
      prometheus
      grafana
    ] ++ optionals cfg.loki.enable [
      grafana-loki
    ];
  };
}
