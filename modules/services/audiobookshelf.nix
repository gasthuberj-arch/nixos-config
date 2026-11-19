{
  config,
  lib,
  mkHardenedService,
  mkHardeningOptions,
  ...
}:
with lib; let
  cfg = config.homelab.services.audiobookshelf;
  caddyCfg = config.homelab.services.caddy;
  stateDir = "/var/lib/${cfg.dataDir}";
in {
  options.homelab.services.audiobookshelf = {
    enable = mkEnableOption "Audiobookshelf audiobook and podcast server";

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for Audiobookshelf web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = "audiobookshelf";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "audiobookshelf";
      description = "Directory name under /var/lib for Audiobookshelf config and metadata";
    };

    mediaDirs = mkOption {
      type = types.listOf types.str;
      default = [
        "/media/audiobooks"
        "/media/podcasts"
      ];
      description = "Media library directories accessible to Audiobookshelf";
    };

    hardening = mkHardeningOptions {
      service = "Audiobookshelf";
      defaultAllowJit = true;
    };
  };

  config = mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      inherit (cfg) port dataDir;
    };

    # Ensure media library directories exist with appropriate ownership
    systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 audiobookshelf audiobookshelf -") cfg.mediaDirs;

    # Persist Audiobookshelf config, database, and metadata across impermanence reboots
    homelab.persistence.directories = [stateDir];

    # Systemd confinement (Node.js/V8 requires JIT; allow access to media libraries)
    systemd.services.audiobookshelf.serviceConfig = mkIf cfg.hardening.enable (mkHardenedService {
      inherit (cfg.hardening) allowJit;
      readWritePaths = [stateDir] ++ cfg.mediaDirs;
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
