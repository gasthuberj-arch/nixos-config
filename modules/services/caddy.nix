{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.caddy-custom;

    myServices = [
      { name = "Immich";         subdomain = "immich";         enable = config.services.immich-custom.enable; }
      { name = "Authelia";       subdomain = "auth";           enable = config.services.authelia-custom.enable; }
      { name = "Paperless";      subdomain = "paperless";      enable = config.services.paperless-custom.enable; }
      { name = "Nextcloud";      subdomain = "nextcloud";      enable = config.services.nextcloud-custom.enable; }
      { name = "Home Assistant"; subdomain = "homeassistant";  enable = config.services.homeassistant-custom.enable; }
      { name = "Grafana";        subdomain = "grafana";        enable = config.services.grafana-custom.enable; }
    ];

    enabledServices = builtins.filter (s: s.enable) myServices;

    serviceListHtml = lib.strings.concatMapStrings (s: ''
      <li class="service-item" data-url="https://${s.subdomain}.${cfg.domain}">
        <a href="https://${s.subdomain}.${cfg.domain}">
          <div class="status-indicator pending"></div>
          <div class="info">
              <span class="name">${s.name}</span>
              <span class="url">https://${s.subdomain}.${cfg.domain}</span>
          </div>
        </a>
      </li>
    '') enabledServices;

    dashboardPkg = pkgs.writeTextDir "index.html" ''
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Homelab Dashboard</title>
        <style>
          :root { --bg: #f0f2f5; --card: #ffffff; --text: #1a202c; --subtext: #718096; --hover: #f7fafc; }
          @media (prefers-color-scheme: dark) {
            :root { --bg: #1a202c; --card: #2d3748; --text: #f7fafc; --subtext: #a0aec0; --hover: #4a5568; }
          }
          body { font-family: -apple-system, system-ui, sans-serif; background: var(--bg); color: var(--text); display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
          .card { background: var(--card); padding: 2rem; border-radius: 16px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); width: 100%; max-width: 450px; }
          h1 { margin-top: 0; font-size: 1.5rem; text-align: center; border-bottom: 2px solid var(--bg); padding-bottom: 1rem; margin-bottom: 1.5rem; }
          ul { list-style: none; padding: 0; margin: 0; }
          li { margin-bottom: 0.75rem; }
          a { display: flex; align-items: center; padding: 1rem; background: var(--bg); border-radius: 10px; text-decoration: none; color: var(--text); transition: transform 0.2s, box-shadow 0.2s; }
          a:hover { transform: translateY(-2px); box-shadow: 0 4px 6px rgba(0,0,0,0.1); background: var(--hover); }
          .info { display: flex; flex-direction: column; margin-left: 12px; }
          .name { font-weight: 600; font-size: 1.1rem; }
          .url { font-size: 0.8rem; color: var(--subtext); margin-top: 2px; }
          .status-indicator { width: 12px; height: 12px; border-radius: 50%; flex-shrink: 0; transition: background 0.3s; }
          .pending { background-color: #cbd5e0; animation: pulse 1.5s infinite; }
          .online { background-color: #48bb78; box-shadow: 0 0 8px #48bb78; }
          .offline { background-color: #f56565; }
          @keyframes pulse { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>🚀 Homelab Status</h1>
          <ul>${serviceListHtml}</ul>
        </div>
        <script>
          document.addEventListener('DOMContentLoaded', () => {
            const services = document.querySelectorAll('.service-item');
            services.forEach(item => {
              const url = item.dataset.url;
              const indicator = item.querySelector('.status-indicator');
              fetch(url, { mode: 'no-cors', cache: 'no-store' })
                .then(() => {
                  indicator.className = 'status-indicator online';
                  indicator.title = 'Online';
                })
                .catch(() => {
                  indicator.className = 'status-indicator offline';
                  indicator.title = 'Offline';
                });
            });
          });
        </script>
      </body>
      </html>
    '';
in
{
  options.services.caddy-custom = {
    enable = mkEnableOption "Caddy reverse proxy";

    domain = mkOption {
      type = types.str;
      default = "homelab.lan";
      description = "Base domain for services";
    };

    email = mkOption {
      type = types.str;
      default = "";
      description = "Email for Let's Encrypt certificates";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Global settings
      globalConfig = ''
        # Admin API endpoint for validation
        admin :2019

        # Explicit storage path for certificates
        storage file_system {
          root /var/lib/caddy/data
        }

        # PKI configuration for internal CA
        pki {
          ca local {
            name "Homelab Local CA"
          }
        }

        ${optionalString (cfg.email != "") ''
          email ${cfg.email}
        ''}
      '';

      # Virtual hosts configuration
      # Note: Using 'tls internal' requires trusting Caddy's internal CA certificate
      # To test with curl: curl -k https://homelab.lan (accepts self-signed certs)
      # Or export the CA cert from /var/lib/caddy/data/caddy/pki/authorities/local/root.crt
      virtualHosts = {
        # Test endpoint to validate Caddy is working (accessible via domain)
        "${cfg.domain}" = {
            extraConfig = ''
              tls internal
              root * ${dashboardPkg}
              file_server
            '';
          };

          # IP-based Access - Serves the same Dashboard
          "https://:443" = {
            extraConfig = ''
              tls internal
              root * ${dashboardPkg}
              file_server
            '';
          };

          "http://:80" = {
            extraConfig = ''
              # Optional: Redirect to HTTPS, or serve dashboard over HTTP
              root * ${dashboardPkg}
              file_server
            '';
          };

        # Immich (if enabled) - accessible via domain
        "immich.${cfg.domain}" = mkIf config.services.immich-custom.enable {
          extraConfig = ''
            tls internal
            reverse_proxy localhost:${toString config.services.immich-custom.port}
          '';
        };

        "auth.${cfg.domain}" = mkIf config.services.authelia-custom.enable {
              extraConfig = ''
                tls internal
                reverse_proxy 127.0.0.1:${toString config.services.authelia-custom.port}
              '';
        };

        # Paperless-ngx (if enabled) - accessible via domain
        "paperless.${cfg.domain}" = mkIf config.services.paperless-custom.enable {
          extraConfig = ''
            tls internal
            reverse_proxy localhost:${toString config.services.paperless-custom.port}
          '';
        };

        # Nextcloud (if enabled) - accessible via domain
        "nextcloud.${cfg.domain}" = mkIf config.services.nextcloud-custom.enable {
          extraConfig = ''
            tls internal
            reverse_proxy localhost:8080 {
              header_up Host {host}
              header_up X-Real-IP {remote_host}
              header_up X-Forwarded-For {remote_host}
              header_up X-Forwarded-Proto {scheme}
            }
          '';
        };

        # Home Assistant (if enabled) - accessible via domain
        "homeassistant.${cfg.domain}" = mkIf config.services.homeassistant-custom.enable {
          extraConfig = ''
            tls internal
            reverse_proxy localhost:${toString config.services.homeassistant-custom.port}
          '';
        };

        # Grafana (if enabled) - accessible via domain
        # Note: Grafana uses native OIDC integration when Authelia is enabled
        # No forward auth needed as Grafana handles OIDC directly
        "grafana.${cfg.domain}" = mkIf config.services.grafana-custom.enable {
          extraConfig = ''
            tls internal
            reverse_proxy localhost:${toString config.services.grafana-custom.port}
          '';
        };

      };
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # Ensure Caddy data directory has correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/caddy 0750 caddy caddy -"
    ];

    # Persist Caddy data across reboots
    environment.persistence."/persist" = {
      directories = [
        {
          directory = "/var/lib/caddy";
          user = "caddy";
          group = "caddy";
          mode = "0750";
        }
      ];
    };
  };
}
