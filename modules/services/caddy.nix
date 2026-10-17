{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.caddy;

  myServices = [
    {
      name = "Immich";
      subdomain = "immich";
      enable = config.homelab.services.immich.enable or false;
    }
    {
      name = "Authelia";
      subdomain = "auth";
      enable = config.homelab.services.authelia.enable or false;
    }
    {
      name = "Paperless";
      subdomain = "paperless";
      enable = config.homelab.services.paperless.enable or false;
    }
    {
      name = "Nextcloud";
      subdomain = "nextcloud";
      enable = config.homelab.services.nextcloud.enable or false;
    }
    {
      name = "Home Assistant";
      subdomain = "homeassistant";
      enable = config.homelab.services.homeassistant.enable or false;
    }
    {
      name = "Grafana";
      subdomain = "grafana";
      enable = config.homelab.services.grafana.enable or false;
    }
    {
      name = "Obsidian Sync";
      subdomain = "obsidian";
      enable = config.homelab.services.obsidian-sync.enable or false;
    }
  ];

  enabledServices = builtins.filter (s: s.enable) myServices;

  serviceListHtml =
    lib.strings.concatMapStrings (s: ''
      <li class="service-item" data-url="https://${s.subdomain}.${cfg.domain}">
        <a href="https://${s.subdomain}.${cfg.domain}">
          <div class="status-indicator pending"></div>
          <div class="info">
              <span class="name">${s.name}</span>
              <span class="url">https://${s.subdomain}.${cfg.domain}</span>
          </div>
        </a>
      </li>
    '')
    enabledServices;

  dashboardPkg = pkgs.writeTextDir "index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Homelab Dashboard</title>
      <style>
        :root { --bg: #f0f2f5; --card: #ffffff; --text: #1a202c; --subtext: #718096; --hover: #f7fafc; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #1a202c; --card: #2d3748; --text: #f7fafc; --subtext: #a0aec0; --hover: #4a5568; }
        }
        body { font-family: -apple-system, system-ui, sans-serif; background: var(--bg); color: var(--text); display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .card { background: var(--card); padding: 2rem; border-radius: 16px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); width: 100%; max-width: 450px; }
        h1 { margin-top: 0; font-size: 1.5rem; text-align: center; border-bottom: 2px solid var(--bg); padding-bottom: 1rem; margin-bottom: 1.5rem; }
        ul { list-style: none; padding: 0; margin: 0; }
        li { margin-bottom: 0.75rem; }
        a { display: flex; align-items: center; padding: 1rem; background: var(--bg); border-radius: 10px; text-decoration: none; color: var(--text); transition: transform 0.2s, box-shadow 0.2s; }
        a:hover { transform: translateY(-2px); box-shadow: 0 4px 6px rgba(0,0,0,0.1); background: var(--hover); }
        .info { display: flex; flex-direction: column; margin-left: 12px; }
        .name { font-weight: 600; font-size: 1.1rem; }
        .url { font-size: 0.8rem; color: var(--subtext); margin-top: 2px; }
        .status-indicator { width: 12px; height: 12px; border-radius: 50%; flex-shrink: 0; transition: background 0.3s; }
        .pending { background-color: #cbd5e0; animation: pulse 1.5s infinite; }
        .online { background-color: #48bb78; box-shadow: 0 0 8px #48bb78; }
        .offline { background-color: #f56565; }
        @keyframes pulse { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>🚀 Homelab Status</h1>
        <ul>${serviceListHtml}</ul>
        <div style="margin-top: 1.5rem; text-align: center; border-top: 1px solid var(--hover); padding-top: 1rem;">
          <a href="/root.crt" download style="display: inline-flex; justify-content: center; font-size: 0.85rem; color: var(--subtext);">
            🔒 Download Root CA Certificate
          </a>
        </div>
      </div>
      <script>
        document.addEventListener('DOMContentLoaded', () => {
          const services = document.querySelectorAll('.service-item');
          services.forEach(item => {
            const url = item.dataset.url;
            const indicator = item.querySelector('.status-indicator');
            fetch(url, { mode: 'no-cors', cache: 'no-store' })
              .then(() => {
                indicator.className = 'status-indicator online';
                indicator.title = 'Online';
              })
              .catch(() => {
                indicator.className = 'status-indicator offline';
                indicator.title = 'Offline';
              });
          });
        });
      </script>
    </body>
    </html>
  '';
in {
  options.homelab.services.caddy = {
    enable = mkEnableOption "Caddy reverse proxy and webserver engine";

    domain = mkOption {
      type = types.str;
      default = "homelab.lan";
      description = "Base domain for homelab services";
    };

    email = mkOption {
      type = types.str;
      default = "";
      description = "Email for Let's Encrypt certificates";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Global settings
      globalConfig = ''
        # Admin API endpoint for validation
        admin :2019

        # Explicit storage path for certificates
        storage file_system {
          root /var/lib/caddy/data
        }

        # PKI configuration for internal CA
        pki {
          ca local {
            name "Homelab Local CA"
          }
        }

        ${optionalString (cfg.email != "") ''
          email ${cfg.email}
        ''}
      '';

      extraConfig = optionalString (config.homelab.services.authelia.enable or false) ''
        (authelia-auth) {
          forward_auth 127.0.0.1:${toString config.homelab.services.authelia.port} {
            uri /api/verify?rd=https://auth.${cfg.domain}/
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
          }
        }
      '';

      virtualHosts = {
        # Landing page dashboard
        "${cfg.domain}" = {
          extraConfig = ''
            tls internal
            handle /root.crt {
              root * /var/lib/caddy/data/pki/authorities/local
              file_server
            }
            root * ${dashboardPkg}
            file_server
          '';
        };

        "https://:443" = {
          extraConfig = ''
            tls internal
            handle /root.crt {
              root * /var/lib/caddy/data/pki/authorities/local
              file_server
            }
            root * ${dashboardPkg}
            file_server
          '';
        };

        "http://:80" = {
          extraConfig = ''
            handle /root.crt {
              root * /var/lib/caddy/data/pki/authorities/local
              file_server
            }
            root * ${dashboardPkg}
            file_server
          '';
        };
      };
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [80 443];

    # Ensure Caddy data directory has correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/caddy 0750 caddy caddy -"
    ];

    # Trust Caddy's internal Root CA across the system
    security.pki.certificates = [
      ''
        -----BEGIN CERTIFICATE-----
        MIIBozCCAUmgAwIBAgIQODPWEKfKrKphOMGSIvPX0jAKBggqhkjOPQQDAjAwMS4w
        LAYDVQQDEyVDYWRkeSBMb2NhbCBBdXRob3JpdHkgLSAyMDI1IEVDQyBSb290MB4X
        DTI1MTIyMzA5MjUyNloXDTM1MTEwMTA5MjUyNlowMDEuMCwGA1UEAxMlQ2FkZHkg
        TG9jYWwgQXV0aG9yaXR5IC0gMjAyNSBFQ0MgUm9vdDBZMBMGByqGSM49AgEGCCqG
        SM49AwEHA0IABINWBJASLt8rbnmtpEwum16cOKU7m/0AUffurkJ36N6js9njlrkV
        dO8zxFN0lXqUtEI0R8V1v0fZiCtkF63tWsmjRTBDMA4GA1UdDwEB/wQEAwIBBjAS
        BgNVHRMBAf8ECDAGAQH/AgEBMB0GA1UdDgQWBBTgLWbiW11Ka4XFKZwlq2jLBmJu
        qjAKBggqhkjOPQQDAgNIADBFAiB3V8qju8RjyDvcdpAtXcKnlvQvVSMzAD6tteGW
        vDJ5UwIhAILNZDGy5qF9GVs9EQBXIR8bNJNhtfH11v7M2Q8CHxCq
        -----END CERTIFICATE-----
      ''
    ];

    # Ensure Node.js and system tools trust the system CA bundle
    environment.variables = {
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
  };
}
