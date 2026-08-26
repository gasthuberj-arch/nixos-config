{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
with lib; let
  cfg = config.homelab.services.homeassistant;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.homeassistant = {
    enable = mkEnableOption "Home Assistant home automation service";

    port = mkOption {
      type = types.port;
      default = 8123;
      description = "Port for Home Assistant web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "homeassistant";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/hass";
      description = "Path to store Home Assistant configuration and data";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for Home Assistant";
    };
  };

  config = mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      package = pkgs-unstable.home-assistant;

      extraComponents = [
        # Core integrations
        "default_config"
        "met"
        "esphome"
        "mqtt"

        # Common device integrations
        "homekit"
        "homekit_controller"
        "hue"
        "cast"
        "spotify"
        "plex"

        # System monitoring
        "systemmonitor"
        "cpuspeed"
      ];

      config = {
        default_config = {};

        http = {
          server_host = "127.0.0.1";
          server_port = cfg.port;
          trusted_proxies = ["127.0.0.1" "::1"];
          use_x_forwarded_for = true;
        };

        frontend = {};
        config = {};
      };
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
