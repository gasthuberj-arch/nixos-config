{
  config,
  lib,
  pkgs,
  mkHardenedService,
  mkHardeningOptions,
  ...
}:
with lib; let
  cfg = config.homelab.services.paperless;
  caddyCfg = config.homelab.services.caddy;
  paperlessHardening = mkHardenedService {
    inherit (cfg.hardening) allowJit;
    readWritePaths = [
      cfg.dataDir
      cfg.mediaDir
      cfg.consumeDir
      (builtins.dirOf (toString cfg.passwordFile))
    ];
  };
in {
  options.homelab.services.paperless = {
    enable = mkEnableOption "Paperless-ngx document management service";

    port = mkOption {
      type = types.port;
      default = 28981;
      description = "Port for Paperless-ngx web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "paperless";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless";
      description = "Path to store Paperless data";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless/media";
      description = "Path to store document files";
    };

    consumeDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless/consume";
      description = "Path to watch for new documents to import";
    };

    passwordFile = mkOption {
      type = types.path;
      default = "/persist/secrets/paperless/admin-password";
      description = "Runtime file containing the Paperless admin password";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Paperless-ngx";
      };
    };

    hardening = mkHardeningOptions {
      service = "Paperless-ngx";
      defaultAllowJit = true;
    };
  };

  config = mkIf cfg.enable {
    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      inherit (cfg) port;
      inherit (cfg) dataDir;
      inherit (cfg) mediaDir;
      consumptionDir = cfg.consumeDir;
      passwordFile = toString cfg.passwordFile;

      settings =
        {
          PAPERLESS_OCR_LANGUAGE = "eng+deu";
          PAPERLESS_TIME_ZONE = "Europe/Berlin";
          PAPERLESS_CONSUMER_RECURSIVE = true;
          PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
          PAPERLESS_ALLOWED_HOSTS = "localhost,127.0.0.1,${cfg.subdomain}.${caddyCfg.domain}";
          PAPERLESS_USE_X_FORWARD_HOST = true;
          PAPERLESS_USE_X_FORWARD_PORT = true;
          PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${cfg.subdomain}.${caddyCfg.domain}";
          PAPERLESS_URL = "https://${cfg.subdomain}.${caddyCfg.domain}";
          PAPERLESS_USE_X_FORWARDED_HOST = true;
          PAPERLESS_USE_X_FORWARDED_PORT = true;
        }
        // optionalAttrs cfg.sso.enable {
          PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
          PAPERLESS_SOCIALACCOUNT_PROVIDERS = builtins.toJSON {
            openid_connect = {
              OAUTH_PKCE_ENABLED = true;
              APPS = [
                {
                  provider_id = "authelia";
                  name = "Authelia";
                  client_id = "paperless";
                  secret = "insecure_secret";
                  settings = {
                    server_url = "https://auth.${caddyCfg.domain}";
                  };
                }
              ];
            };
          };
        };
    };

    # Ensure directories exist and have correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 paperless paperless -"
      "d ${cfg.mediaDir} 0750 paperless paperless -"
      "d ${cfg.consumeDir} 0750 paperless paperless -"
      "Z ${cfg.dataDir} 0750 paperless paperless -"
      "d ${builtins.dirOf (toString cfg.passwordFile)} 0700 paperless paperless -"
    ];

    # Generate Paperless runtime admin password if missing
    systemd.services.paperless-generate-secrets = {
      description = "Generate Paperless admin password file if missing";
      wantedBy = ["multi-user.target"];
      before = [
        "paperless-scheduler.service"
        "paperless-web.service"
        "paperless-consumer.service"
        "paperless-task-queue.service"
      ];
      script = ''
        PASS_FILE="${toString cfg.passwordFile}"
        SECRETS_DIR="$(dirname "$PASS_FILE")"
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        if [ ! -f "$PASS_FILE" ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 32 > "$PASS_FILE"
          chmod 600 "$PASS_FILE"
        fi
        if id paperless &>/dev/null; then
          chown -R paperless:paperless "$SECRETS_DIR"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Register persistent state directories and runtime secret paths
    homelab.persistence.directories = [
      cfg.dataDir
      "/var/lib/redis-paperless"
    ];
    homelab.hardening.secretPaths = [(toString cfg.passwordFile)];

    # Fix permissions on existing directories before services start
    systemd.services.paperless-fix-permissions = {
      description = "Fix Paperless directory permissions";
      wantedBy = ["multi-user.target"];
      after = ["systemd-tmpfiles-setup.service"];
      before = [
        "paperless-scheduler.service"
        "paperless-web.service"
        "paperless-consumer.service"
        "paperless-task-queue.service"
      ];
      script = ''
        if [ -d ${cfg.dataDir} ] && id paperless &>/dev/null; then
          chown -R paperless:paperless ${cfg.dataDir} || true
          chmod -R 0750 ${cfg.dataDir} || true
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Systemd confinement
    systemd.services.paperless-web.serviceConfig = mkIf cfg.hardening.enable paperlessHardening;
    systemd.services.paperless-consumer.serviceConfig = mkIf cfg.hardening.enable paperlessHardening;
    systemd.services.paperless-scheduler.serviceConfig = mkIf cfg.hardening.enable paperlessHardening;
    systemd.services.paperless-task-queue.serviceConfig = mkIf cfg.hardening.enable paperlessHardening;

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';
    };
  };
}
