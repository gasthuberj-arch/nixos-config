{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.vaultwarden;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager service";

    port = mkOption {
      type = types.port;
      default = 8222;
      description = "Port for Vaultwarden web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "vaultwarden";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/vaultwarden";
      description = "Path to store Vaultwarden data";
    };

    signupsAllowed = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to allow user registrations";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/persist/secrets/vaultwarden/vaultwarden.env";
      description = "Path to environment file containing secrets like SSO_CLIENT_SECRET and ADMIN_TOKEN";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Vaultwarden";
      };

      authority = mkOption {
        type = types.str;
        default = "https://auth.${caddyCfg.domain}";
        description = "Authority URL for OIDC provider";
      };

      clientId = mkOption {
        type = types.str;
        default = "vaultwarden";
        description = "Client ID for OIDC provider";
      };
    };
  };

  config = mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      inherit (cfg) environmentFile;
      config =
        {
          DOMAIN = "https://${cfg.subdomain}.${caddyCfg.domain}";
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = cfg.port;
          DATA_FOLDER = cfg.dataDir;
          SIGNUPS_ALLOWED = cfg.signupsAllowed;
        }
        // optionalAttrs cfg.sso.enable {
          SSO_ENABLED = true;
          SSO_ONLY = false;
          SSO_AUTHORITY = cfg.sso.authority;
          SSO_CLIENT_ID = cfg.sso.clientId;
          SSO_SCOPES = "openid profile email offline_access";
          SSO_PKCE = true;
          SSO_SIGNUPS_MATCH_EMAIL = true;
        };
    };

    # Create secret generation service if not already existing
    systemd.services.vaultwarden-generate-secrets = {
      description = "Generate Vaultwarden secrets if they don't exist";
      wantedBy = ["multi-user.target"];
      before = ["vaultwarden.service"];

      script = ''
                SECRETS_DIR="$(dirname "${toString cfg.environmentFile}")"
                mkdir -p "$SECRETS_DIR"
                chmod 700 "$SECRETS_DIR"

                if [ ! -f "${toString cfg.environmentFile}" ]; then
                  echo "Generating Vaultwarden environment secret file..."
                  ADMIN_TOKEN=$(${pkgs.openssl}/bin/openssl rand -base64 48)
                  cat <<EOF > "${toString cfg.environmentFile}"
        SSO_CLIENT_SECRET=insecure_secret
        ADMIN_TOKEN=$ADMIN_TOKEN
        EOF
                  chmod 600 "${toString cfg.environmentFile}"
                fi

                chown -R vaultwarden:vaultwarden "$SECRETS_DIR"
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Ensure permissions for data and secrets directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 vaultwarden vaultwarden -"
      "d /persist/secrets/vaultwarden 0700 vaultwarden vaultwarden -"
    ];

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port} {
          header_down -Cross-Origin-Resource-Policy
        }
      '';
    };
  };
}
