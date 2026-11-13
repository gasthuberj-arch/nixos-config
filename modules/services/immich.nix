{
  config,
  lib,
  pkgs-unstable,
  mkHardenedService,
  mkHardeningOptions,
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

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = "/persist/secrets/immich/immich.env";
      description = "Path to environment secrets file for Immich";
    };

    sso = {
      enable = mkOption {
        type = types.bool;
        default = config.homelab.services.authelia.enable or false;
        description = "Enable Authelia OIDC SSO for Immich";
      };
    };

    hardening = mkHardeningOptions {
      service = "Immich";
      defaultAllowJit = true;
      allowGpuOption = true;
      defaultAllowGpu = true;
    };
  };

  config = mkIf cfg.enable {
    services.immich = {
      enable = true;
      host = "127.0.0.1";
      inherit (cfg) port mediaLocation secretsFile;
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
    systemd.tmpfiles.rules =
      [
        "d ${cfg.mediaLocation} 0750 immich immich -"
        "d ${cfg.uploadLocation} 0750 immich immich -"
      ]
      ++ optional (cfg.secretsFile != null) "d ${builtins.dirOf (toString cfg.secretsFile)} 0700 immich immich -";

    # Ensure Immich runtime secrets file exists
    systemd.services.immich-generate-secrets = mkIf (cfg.secretsFile != null) {
      description = "Initialize Immich runtime secrets file if missing";
      wantedBy = ["multi-user.target"];
      before = ["immich-server.service" "immich-machine-learning.service"];
      script = ''
        SECRETS_FILE="${toString cfg.secretsFile}"
        SECRETS_DIR="$(dirname "$SECRETS_FILE")"
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        if [ ! -f "$SECRETS_FILE" ]; then
          cat <<EOF > "$SECRETS_FILE"
        # Managed at runtime on host; populate secrets as needed
        EOF
          chmod 600 "$SECRETS_FILE"
        fi
        chown -R immich:immich "$SECRETS_DIR"
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Register persistent state directories and runtime secret paths
    homelab.persistence.directories = [
      "/var/lib/immich"
      "/var/lib/postgresql"
      "/var/lib/redis-immich"
    ];

    homelab.hardening.secretPaths = optional (cfg.secretsFile != null) (toString cfg.secretsFile);

    # Systemd confinement
    systemd.services.immich-server.serviceConfig = mkIf cfg.hardening.enable (mkHardenedService {
      inherit (cfg.hardening) allowJit allowGpu;
      readWritePaths = [cfg.mediaLocation cfg.uploadLocation "/var/lib/immich"];
    });

    systemd.services.immich-machine-learning.serviceConfig = mkIf cfg.hardening.enable (mkHardenedService {
      inherit (cfg.hardening) allowJit allowGpu;
      readWritePaths = ["/var/lib/immich"];
    });

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        request_body {
          max_size 50GB
        }
        reverse_proxy 127.0.0.1:${toString cfg.port} {
          transport http {
            response_header_timeout 600s
          }
        }
      '';
    };
  };
}
