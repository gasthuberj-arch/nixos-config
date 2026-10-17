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

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Immich";
      };
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

      settings = mkIf cfg.sso.enable {
        server.externalDomain = "https://${cfg.subdomain}.${caddyCfg.domain}";
        oauth = {
          enabled = true;
          autoLaunch = false;
          autoRegister = true;
          buttonText = "Login with Authelia";
          clientId = "immich";
          clientSecret = "insecure_secret";
          issuerUrl = "https://auth.${caddyCfg.domain}";
          scope = "openid profile email";
        };
      };
    };

    # Ensure Immich server trusts internal Caddy certificates for OIDC discovery
    systemd.services.immich-server.environment.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";

    # Ensure Immich waits for the media location to be mounted
    systemd.services.immich-server.unitConfig.RequiresMountsFor = [cfg.mediaLocation];

    # Ensure media directory exists and has correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.mediaLocation} 0750 immich immich -"
      "d ${cfg.uploadLocation} 0750 immich immich -"
    ];

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        request_body {
          max_size 50GB
        }
        reverse_proxy localhost:${toString cfg.port} {
          transport http {
            response_header_timeout 600s
          }
        }
      '';
    };
  };
}
