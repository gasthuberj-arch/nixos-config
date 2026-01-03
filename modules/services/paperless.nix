{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.paperless-custom;
in {
  options.services.paperless-custom = {
    enable = mkEnableOption "Paperless-ngx document management service";

    port = mkOption {
      type = types.port;
      default = 28981;
      description = "Port for Paperless-ngx web interface";
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

      # Admin password - set via passwordFile or use default
      passwordFile =
        if cfg.passwordFile != null
        then cfg.passwordFile
        else null;

      # Paperless settings
      settings = {
        PAPERLESS_OCR_LANGUAGE = "eng+deu";
        PAPERLESS_TIME_ZONE = "Europe/Berlin";
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
        # Allow access from reverse proxy
        PAPERLESS_ALLOWED_HOSTS = "localhost,127.0.0.1,paperless.homelab.lan";
        # Trust proxy headers
        PAPERLESS_USE_X_FORWARD_HOST = true;
        PAPERLESS_USE_X_FORWARD_PORT = true;
        PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://paperless.homelab.lan";
        PAPERLESS_URL = "https://paperless.homelab.lan";
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

    # Persist Paperless data across reboots
    environment.persistence."/persist" = {
      directories = [
        {
          directory = cfg.dataDir;
          user = "paperless";
          group = "paperless";
          mode = "0750";
        }
      ];
    };
  };
}
