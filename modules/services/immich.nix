{ config, lib, pkgs, pkgs-unstable, ... }:

with lib;

let
  cfg = config.services.immich-custom;
in
{
  options.services.immich-custom = {
    enable = mkEnableOption "Immich photo management service";

    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Port for Immich web interface";
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
      port = cfg.port;

      # Use unstable version for latest features
      package = pkgs-unstable.immich;

      # Media storage location
      mediaLocation = cfg.mediaLocation;

      # Database configuration
      database = {
        enable = true;
        createDB = true;
      };

      # Redis configuration
      redis = {
        enable = true;
      };

      # Machine learning configuration
      machine-learning = {
        enable = true;
      };
    };

    # Ensure media directory exists and has correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.mediaLocation} 0750 immich immich -"
      "d ${cfg.uploadLocation} 0750 immich immich -"
    ];

    # Persist Immich data across reboots
    environment.persistence."/persist" = {
      directories = [
        {
          directory = "/var/lib/immich";
          user = "immich";
          group = "immich";
          mode = "0750";
        }
        {
          directory = "/var/lib/postgresql";
          user = "postgres";
          group = "postgres";
          mode = "0750";
        }
        {
          directory = "/var/lib/redis-immich";
          user = "redis-immich";
          group = "redis-immich";
          mode = "0750";
        }
      ];
    };

    # Note: Media location (/pictures) is already persisted via ZFS mount
    # No need to add it to environment.persistence
  };
}
