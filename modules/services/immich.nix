{
  config,
  lib,
  pkgs-unstable,
  ...
}:
with lib; let
  cfg = config.homelab.services.immich;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.immich = {
    enable = mkEnableOption "Immich photo management service";

    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Port for Immich web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "immich";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    mediaLocation = mkOption {
      type = types.str;
      default = "/pictures/immich";
      description = "Path to store Immich photos and videos";
    };

    uploadLocation = mkOption {
      type = types.str;
      default = "/var/lib/immich/upload";
      description = "Path to store uploaded files";
    };
  };

  config = mkIf cfg.enable {
    services.immich = {
      enable = true;
      inherit (cfg) port mediaLocation;
      package = pkgs-unstable.immich;

      database = {
        enable = true;
        createDB = true;
      };

      redis = {
        enable = true;
      };

      machine-learning = {
        enable = true;
      };
    };

    # Ensure media directory exists and has correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.mediaLocation} 0750 immich immich -"
      "d ${cfg.uploadLocation} 0750 immich immich -"
    ];

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
