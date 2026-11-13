{
  config,
  lib,
  pkgs,
  mkHardenedService,
  mkHardeningOptions,
  ...
}:
with lib; let
  cfg = config.homelab.services.nextcloud;
in {
  options.homelab.services.nextcloud = {
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
      type = types.path;
      default = "/persist/secrets/nextcloud/admin-password";
      description = "Runtime file containing the Nextcloud admin password";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Nextcloud";
      };
    };

    hardening = mkHardeningOptions {
      service = "Nextcloud PHP-FPM";
      defaultAllowJit = true;
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.nextcloud = {
        enable = true;
        # Bump one major at a time: Nextcloud refuses to skip versions, and
        # nextcloud-setup runs the occ upgrade (DB migration) on switch.
        package = pkgs.nextcloud33;
        inherit (cfg) hostName;
        datadir = cfg.dataDir;

        # HTTPS configuration - will be handled by Caddy reverse proxy
        https = true;

        # Max upload size
        inherit (cfg) maxUploadSize;

        # Database configuration - use PostgreSQL
        database.createLocally = true;

        # Admin account
        config = {
          adminuser = cfg.adminUser;
          adminpassFile = toString cfg.adminPasswordFile;

          dbtype = "pgsql";
          dbhost = "/run/postgresql";
        };

        # Extra apps for OIDC SSO
        extraApps = mkIf cfg.sso.enable {
          inherit (config.services.nextcloud.package.packages.apps) oidc_login;
        };
        extraAppsEnable = mkIf cfg.sso.enable true;

        # Additional settings
        settings =
          {
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
          }
          // optionalAttrs cfg.sso.enable {
            oidc_login_provider_url = "https://auth.${config.homelab.services.caddy.domain}";
            oidc_login_client_id = "nextcloud";
            oidc_login_client_secret = "insecure_secret";
            oidc_login_auto_redirect = false;
            oidc_login_button_text = "Log in with Authelia";
            oidc_login_hide_password_form = false;
            oidc_login_use_id_token = false;
            oidc_login_scope = "openid profile email groups";
            oidc_login_attributes = {
              id = "preferred_username";
              name = "name";
              mail = "email";
              groups = "groups";
            };
            oidc_login_default_group = "users";
            oidc_login_use_external_storage = false;
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
        "d ${builtins.dirOf (toString cfg.adminPasswordFile)} 0700 nextcloud nextcloud -"
      ];

      # Register persistent state directories and runtime secret paths
      homelab.persistence.directories = [
        cfg.dataDir
        "/var/lib/postgresql"
        "/var/lib/redis-nextcloud"
      ];
      homelab.hardening.secretPaths = [(toString cfg.adminPasswordFile)];

      # Generate Nextcloud admin password at runtime if missing
      systemd.services.nextcloud-generate-secrets = {
        description = "Generate Nextcloud admin password file if missing";
        wantedBy = ["multi-user.target"];
        before = ["nextcloud-setup.service" "phpfpm-nextcloud.service"];
        script = ''
          PASS_FILE="${toString cfg.adminPasswordFile}"
          SECRETS_DIR="$(dirname "$PASS_FILE")"
          mkdir -p "$SECRETS_DIR"
          chmod 700 "$SECRETS_DIR"
          if [ ! -f "$PASS_FILE" ]; then
            ${pkgs.openssl}/bin/openssl rand -base64 32 > "$PASS_FILE"
            chmod 600 "$PASS_FILE"
          fi
          if id nextcloud &>/dev/null; then
            chown -R nextcloud:nextcloud "$SECRETS_DIR"
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

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
        wants = ["nextcloud-fix-permissions.service" "nextcloud-generate-secrets.service"];
        after = ["nextcloud-fix-permissions.service" "nextcloud-generate-secrets.service"];
        preStart = ''
          ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${cfg.dataDir}/config
        '';
      };

      # Systemd confinement
      systemd.services.phpfpm-nextcloud.serviceConfig = mkIf cfg.hardening.enable (mkHardenedService {
        inherit (cfg.hardening) allowJit;
        readWritePaths = [cfg.dataDir (builtins.dirOf (toString cfg.adminPasswordFile))];
      });

      # Self-register in Caddy reverse proxy
      services.caddy.virtualHosts."${cfg.hostName}" = mkIf config.homelab.services.caddy.enable {
        extraConfig = ''
          tls internal
          reverse_proxy 127.0.0.1:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
          }
        '';
      };
    })

    # Configure nginx outside of the main mkIf to avoid scoping issues
    (mkIf cfg.enable {
      # Configure nginx to listen strictly on loopback port 8080 (Caddy handles external TLS)
      services.nginx = {
        defaultHTTPListenPort = 8080;
        defaultSSLListenPort = 8443;
        virtualHosts.${cfg.hostName}.listen = [
          {
            addr = "127.0.0.1";
            port = 8080;
          }
        ];
      };
    })
  ];
}
