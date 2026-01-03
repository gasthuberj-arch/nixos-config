{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.caddy-custom;
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
            respond "Caddy is working! 🎉" 200
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

        # IP-based access (HTTP only)
        "http://:80" = {
          extraConfig = ''
            respond "Caddy is working via IP! 🎉\n\nFor HTTPS, use: https://homelab.lan, https://auth.homelab.lan, https://immich.homelab.lan, https://paperless.homelab.lan, https://nextcloud.homelab.lan, https://homeassistant.homelab.lan, or https://grafana.homelab.lan" 200
          '';
        };

        # IP-based HTTPS access (fallback/default)
        "https://:443" = {
          extraConfig = ''
            tls internal
            respond "Caddy HTTPS is working via IP! 🎉\n\nFor named services, use: https://homelab.lan, https://auth.homelab.lan, https://immich.homelab.lan, https://paperless.homelab.lan, https://nextcloud.homelab.lan, https://homeassistant.homelab.lan, or https://grafana.homelab.lan" 200
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
