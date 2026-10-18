{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.homelab.services.gatus;
  caddyCfg = config.homelab.services.caddy;

  # Build default endpoints based on which homelab services are enabled
  defaultEndpoints =
    optionals (config.homelab.services.authelia.enable or false) [
      {
        name = "Authelia";
        group = "Core";
        url = "https://auth.${caddyCfg.domain}/api/health";
        interval = "30s";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (caddyCfg.enable or false) [
      {
        name = "Homepage";
        group = "Core";
        url = "https://${caddyCfg.domain}";
        interval = "1m";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (config.homelab.services.vaultwarden.enable or false) [
      {
        name = "Vaultwarden";
        group = "Security";
        url = "https://vaultwarden.${caddyCfg.domain}/alive";
        interval = "1m";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (config.homelab.services.grafana.enable or false) [
      {
        name = "Grafana";
        group = "Observability";
        url = "https://grafana.${caddyCfg.domain}/api/health";
        interval = "1m";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (config.homelab.services.immich.enable or false) [
      {
        name = "Immich";
        group = "Media";
        url = "https://immich.${caddyCfg.domain}/api/server/ping";
        interval = "1m";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (config.homelab.services.paperless.enable or false) [
      {
        name = "Paperless-ngx";
        group = "Productivity";
        url = "https://paperless.${caddyCfg.domain}";
        interval = "1m";
        conditions = ["[STATUS] < 400"];
      }
    ]
    ++ optionals (config.homelab.services.nextcloud.enable or false) [
      {
        name = "Nextcloud";
        group = "Productivity";
        url = "https://nextcloud.${caddyCfg.domain}/status.php";
        interval = "1m";
        conditions = ["[STATUS] == 200"];
      }
    ]
    ++ optionals (config.homelab.services.homeassistant.enable or false) [
      {
        name = "Home Assistant";
        group = "Automation";
        url = "https://homeassistant.${caddyCfg.domain}";
        interval = "1m";
        conditions = ["[STATUS] == any(200, 302, 401)"];
      }
    ]
    ++ optionals (config.homelab.services.obsidian-sync.enable or false) [
      {
        name = "Obsidian Sync";
        group = "Productivity";
        url = "https://obsidian.${caddyCfg.domain}";
        interval = "1m";
        conditions = ["[STATUS] == any(200, 401)"];
      }
    ];
in {
  options.homelab.services.gatus = {
    enable = mkEnableOption "Gatus declarative service health dashboard";

    port = mkOption {
      type = types.port;
      default = 3001;
      description = "Port for Gatus web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "status";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    extraEndpoints = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Additional Gatus endpoint configurations to monitor";
    };

    alerting = mkOption {
      type = types.attrs;
      default = {};
      description = "Gatus alerting configuration (Discord, Telegram, Ntfy, Pushover, etc.)";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Authelia forward authentication for Gatus status page";
      };
    };
  };

  config = mkIf cfg.enable {
    # System user & group for impermanence compatibility (avoids DynamicUser rename bug)
    users.users.gatus = {
      isSystemUser = true;
      group = "gatus";
      home = "/var/lib/gatus";
    };
    users.groups.gatus = {};

    # Declarative Gatus service configuration
    services.gatus = {
      enable = true;
      settings = {
        web.port = cfg.port;

        storage = {
          type = "sqlite";
          path = "/var/lib/gatus/data.db";
        };

        ui = {
          title = "Homelab Status";
          header = "Homelab Status";
          description = "Declarative real-time status of homelab services";
        };

        endpoints = defaultEndpoints ++ cfg.extraEndpoints;

        alerting = mkIf (cfg.alerting != {}) cfg.alerting;
      };
    };

    # Override DynamicUser so bind-mounted /var/lib/gatus is not renamed to /var/lib/private/gatus
    systemd.services.gatus.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gatus";
      Group = "gatus";
      PrivateUsers = lib.mkForce false;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/gatus 0750 gatus gatus -"
      "Z /var/lib/gatus 0750 gatus gatus -"
    ];

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        ${optionalString cfg.sso.enable ''
          @needsAuth {
            not path /api/v1/endpoints/*/badge/*
            not path /assets/*
            not path /favicon.ico
          }
          forward_auth @needsAuth 127.0.0.1:${toString config.homelab.services.authelia.port} {
            uri /api/verify?rd=https://auth.${caddyCfg.domain}/
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
          }
        ''}
        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
