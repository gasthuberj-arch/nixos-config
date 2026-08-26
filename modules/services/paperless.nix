{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.paperless;
  caddyCfg = config.homelab.services.caddy;
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
      type = types.nullOr types.path;
      default = null;
      description = "File containing the admin password (will use default if not set)";
    };
  };

  config = mkIf cfg.enable {
    services.paperless = {
      enable = true;
      port = cfg.port;
      dataDir = cfg.dataDir;
      mediaDir = cfg.mediaDir;
      consumptionDir = cfg.consumeDir;

      passwordFile =
        if cfg.passwordFile != null
        then cfg.passwordFile
        else null;

      settings = {
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
      };
    };

    # Ensure directories exist and have correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 paperless paperless -"
      "d ${cfg.mediaDir} 0750 paperless paperless -"
      "d ${cfg.consumeDir} 0750 paperless paperless -"
      "Z ${cfg.dataDir} 0750 paperless paperless -"
    ];

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

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
