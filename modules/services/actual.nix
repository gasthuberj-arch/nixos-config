{
  config,
  lib,
  mkHardenedService,
  mkHardeningOptions,
  ...
}:
with lib; let
  cfg = config.homelab.services.actual;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.actual = {
    enable = mkEnableOption "Actual Budget local-first personal finance server";

    port = mkOption {
      type = types.port;
      default = 5006;
      description = "Port for Actual Budget web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "actual";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/actual";
      description = "Path to store Actual Budget server and user data";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Actual Budget";
      };
    };

    hardening = mkHardeningOptions {
      service = "Actual Budget";
      defaultAllowJit = true;
    };
  };

  config = mkIf cfg.enable {
    # System user & group for impermanence compatibility (avoids DynamicUser /var/lib/private rename bug)
    users.users.actual = {
      isSystemUser = true;
      group = "actual";
      home = cfg.dataDir;
    };
    users.groups.actual = {};

    services.actual = {
      enable = true;
      user = "actual";
      group = "actual";
      settings =
        {
          hostname = "127.0.0.1";
          inherit (cfg) port dataDir;
        }
        // optionalAttrs cfg.sso.enable {
          loginMethod = "openid";
          openId = {
            discoveryURL = "https://auth.${caddyCfg.domain}";
            client_id = "actual";
            client_secret = "insecure_secret";
            server_hostname = "https://${cfg.subdomain}.${caddyCfg.domain}";
            authMethod = "oauth2";
          };
        };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 actual actual -"
      "d ${cfg.dataDir}/server-files 0700 actual actual -"
      "d ${cfg.dataDir}/user-files 0700 actual actual -"
      "Z ${cfg.dataDir} 0700 actual actual -"
    ];

    # Persist Actual Budget state across impermanence reboots
    homelab.persistence.directories = [cfg.dataDir];

    # Systemd confinement (Node.js/V8 requires JIT)
    systemd.services.actual.serviceConfig = mkIf cfg.hardening.enable (mkHardenedService {
      inherit (cfg.hardening) allowJit;
      readWritePaths = [cfg.dataDir];
    });

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';
    };
  };
}
