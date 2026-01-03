{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
with lib; let
  cfg = config.services.homeassistant-custom;
in {
  options.services.homeassistant-custom = {
    enable = mkEnableOption "Home Assistant home automation service";

    port = mkOption {
      type = types.port;
      default = 8123;
      description = "Port for Home Assistant web interface";
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

      # Use unstable version for latest features and integrations
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
        # Basic configuration
        default_config = {};

        http = {
          server_host = "127.0.0.1";
          server_port = cfg.port;
          trusted_proxies = ["127.0.0.1" "::1"];
          use_x_forwarded_for = true;
        };

        # Enable the frontend
        frontend = {};

        # Enable the config panel
        config = {};
      };
    };

    # Persist Home Assistant data across reboots
    environment.persistence."/persist" = {
      directories = [
        {
          directory = cfg.dataDir;
          user = "hass";
          group = "hass";
          mode = "0750";
        }
      ];
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
