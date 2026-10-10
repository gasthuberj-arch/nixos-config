{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.homelab.services.headscale;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.headscale = {
    enable = mkEnableOption "Headscale coordination server for Tailscale";

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind Headscale to";
    };

    port = mkOption {
      type = types.port;
      default = 8085;
      description = "Port for the Headscale HTTP/gRPC server";
    };

    serverUrl = mkOption {
      type = types.str;
      default = "http://192.168.1.101:${toString cfg.port}";
      description = "The url clients will connect to";
    };

    baseDomain = mkOption {
      type = types.str;
      default = "homelab.lan";
      description = "Base domain for MagicDNS";
    };

    tailscaleIp = mkOption {
      type = types.str;
      default = "100.64.0.1";
      description = "Expected Tailscale IP of the homelab node for extra DNS records";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the Headscale port in the firewall";
    };
  };

  config = mkIf cfg.enable {
    services.headscale = {
      enable = true;
      inherit (cfg) address port;

      settings = {
        server_url = cfg.serverUrl;

        # DERP Configuration - Use Tailscale's official DERP map
        derp = {
          server.enabled = false; # Do not host internal DERP relay
          urls = [
            "https://controlplane.tailscale.com/derpmap/default"
          ];
          auto_update_enabled = true;
          update_frequency = "24h";
        };

        # MagicDNS Configuration
        dns = {
          magic_dns = true;
          base_domain = cfg.baseDomain;
          nameservers.global = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          extra_records = [
            {
              name = "homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "auth.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "immich.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "paperless.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "nextcloud.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "homeassistant.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "grafana.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
            {
              name = "obsidian.homelab.lan";
              type = "A";
              value = cfg.tailscaleIp;
            }
          ];
        };
      };
    };

    # Open firewall port for Headscale
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];

    # Trust tailscale interface
    networking.firewall.trustedInterfaces = ["tailscale0"];

    # Reverse proxy via Caddy if enabled
    services.caddy.virtualHosts."headscale.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port} {
          header_up Host {host}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
  };
}
