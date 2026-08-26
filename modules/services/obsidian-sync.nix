{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.obsidian-sync;
  caddyCfg = config.homelab.services.caddy;
in {
  options.homelab.services.obsidian-sync = {
    enable = mkEnableOption "Obsidian LiveSync Server (CouchDB)";

    port = mkOption {
      type = types.port;
      default = 5984;
      description = "Port for the CouchDB sync server";
    };

    subdomain = mkOption {
      type = types.str;
      default = "obsidian";
      description = "Subdomain prefix for Caddy reverse proxy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/couchdb";
      description = "Path to store the sync database";
    };
  };

  config = mkIf cfg.enable {
    services.couchdb = {
      enable = true;
      port = cfg.port;
      bindAddress = "127.0.0.1";
      databaseDir = cfg.dataDir;

      extraConfig = {
        httpd = {
          enable_cors = "true";
          max_http_request_size = "4294967296";
        };

        chttpd = {
          require_valid_user = "true";
          bind_address = "127.0.0.1";
        };

        cors = {
          origins = "app://obsidian.md,capacitor://localhost,http://localhost";
          credentials = "true";
          headers = "accept, authorization, content-type, origin, referer";
          methods = "GET, PUT, POST, HEAD, DELETE";
        };

        couch_httpd_auth = {
          require_valid_user = "true";
          allow_persistent_cookies = "true";
        };
      };
    };

    # Ensure Data Directory exists with permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0770 couchdb couchdb -"
    ];

    # Setup Script: Create the 'obsidian' database automatically
    systemd.services.obsidian-sync-init = {
      description = "Initialize Obsidian Sync Database";
      wantedBy = ["multi-user.target"];
      after = ["couchdb.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "couchdb";
        Group = "couchdb";
      };
      script = ''
        while ! ${pkgs.curl}/bin/curl -s http://127.0.0.1:${toString cfg.port}/_up > /dev/null; do
          sleep 2
        done

        ${pkgs.curl}/bin/curl -X PUT http://127.0.0.1:${toString cfg.port}/obsidian || true
      '';
    };

    # Self-register in Caddy reverse proxy
    services.caddy.virtualHosts."${cfg.subdomain}.${caddyCfg.domain}" = mkIf caddyCfg.enable {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.port} {
          header_up Host {host}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
  };
}
