{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.nextcloud-custom;
in {
  options.services.nextcloud-custom = {
    enable = mkEnableOption "Nextcloud self-hosted cloud service";

    hostName = mkOption {
      type = types.str;
      default = "nextcloud.homelab.lan";
      description = "Hostname for Nextcloud instance";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/nextcloud";
      description = "Path to store Nextcloud data";
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "16G";
      description = "Maximum upload size for files";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Admin username";
    };

    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the admin password";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.nextcloud = {
        enable = true;
        package = pkgs.nextcloud32;
        hostName = cfg.hostName;
        datadir = cfg.dataDir;

        # HTTPS configuration - will be handled by Caddy reverse proxy
        https = true;

        # Max upload size
        maxUploadSize = cfg.maxUploadSize;

        # Database configuration - use PostgreSQL
        database.createLocally = true;

        # Admin account
        config = {
          adminuser = cfg.adminUser;
          adminpassFile =
            if cfg.adminPasswordFile != null
            then cfg.adminPasswordFile
            else toString (pkgs.writeText "nextcloud-admin-pass" "changeme");

          dbtype = "pgsql";
          dbhost = "/run/postgresql";
        };

        # Additional settings
        settings = {
          # Trust proxy headers from Caddy
          trusted_proxies = ["127.0.0.1" "::1"];
          overwriteprotocol = "https";

          # Performance settings
          "memcache.local" = "\\OC\\Memcache\\APCu";
          "memcache.distributed" = "\\OC\\Memcache\\Redis";
          "memcache.locking" = "\\OC\\Memcache\\Redis";
          redis = {
            host = "/run/redis-nextcloud/redis.sock";
            port = 0;
          };

          # Default phone region
          default_phone_region = "DE";

          # Maintenance window (UTC time, 3 AM CET = 2 AM UTC)
          maintenance_window_start = 2;
        };

        # Enable APCu for local caching
        phpOptions = {
          "apc.enable_cli" = "1";
        };

        # Auto-update apps
        autoUpdateApps.enable = true;
        autoUpdateApps.startAt = "05:00:00";
      };

      # Redis for caching
      services.redis.servers.nextcloud = {
        enable = true;
        user = "nextcloud";
        port = 0; # Use unix socket
      };

      # Ensure data directory has correct permissions
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 nextcloud nextcloud -"
        "d ${cfg.dataDir}/config 0750 nextcloud nextcloud -"
        "d ${cfg.dataDir}/data 0750 nextcloud nextcloud -"
        "Z ${cfg.dataDir} 0750 nextcloud nextcloud -"
      ];

      # Fix permissions on existing directories before services start
      systemd.services.nextcloud-fix-permissions = {
        description = "Fix Nextcloud directory permissions";
        wantedBy = ["multi-user.target"];
        after = ["systemd-tmpfiles-setup.service"];
        before = ["nextcloud-setup.service" "phpfpm-nextcloud.service"];
        script = ''
          if [ -d ${cfg.dataDir} ]; then
            chown -R nextcloud:nextcloud ${cfg.dataDir} || true
            chmod -R 0750 ${cfg.dataDir} || true
          fi
          if [ -d /var/lib/redis-nextcloud ] && id redis-nextcloud &>/dev/null; then
            chown -R redis-nextcloud:redis-nextcloud /var/lib/redis-nextcloud || true
            chmod -R 0750 /var/lib/redis-nextcloud || true
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      # Ensure nextcloud-setup refreshes declarative override.config.php symlink before running migrations
      systemd.services.nextcloud-setup = {
        wants = ["nextcloud-fix-permissions.service"];
        after = ["nextcloud-fix-permissions.service"];
        preStart = ''
          ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${cfg.dataDir}/config
        '';
      };

      # Persist Nextcloud data across reboots
      environment.persistence."/persist" = {
        directories = [
          {
            directory = cfg.dataDir;
            user = "nextcloud";
            group = "nextcloud";
            mode = "0750";
          }
          # Note: /var/lib/postgresql is already persisted by immich.nix
          # since both services share the same PostgreSQL instance
          {
            directory = "/var/lib/redis-nextcloud";
            user = "redis-nextcloud";
            group = "redis-nextcloud";
            mode = "0750";
          }
        ];
      };
    })

    # Configure nginx outside of the main mkIf to avoid scoping issues
    (mkIf cfg.enable {
      # Configure nginx to listen on port 8080 (not 80, since Caddy uses that)
      services.nginx = {
        defaultHTTPListenPort = 8080;
        defaultSSLListenPort = 8443;
      };
    })
  ];
}
