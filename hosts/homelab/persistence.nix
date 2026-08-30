_: {
  # Impermanence - centralized state persistence for homelab
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/NetworkManager"
      "/var/lib/tailscale"
      "/var/lib/caddy"
      "/var/lib/authelia-main"
      "/var/lib/immich"
      "/var/lib/paperless"
      "/var/lib/nextcloud"
      "/var/lib/hass"
      "/var/lib/grafana"
      "/var/lib/prometheus2"
      "/var/lib/loki"
      "/var/lib/couchdb"
      "/var/lib/postgresql"
      "/var/lib/redis-immich"
      "/var/lib/redis-paperless"
      "/var/lib/redis-nextcloud"
      "/var/lib/sunshine"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
    users.johannes = {
      directories = [
        "Downloads"
        "Documents"
        "Pictures"
        "Videos"
        ".config"
        ".local"
        ".ssh"
      ];
    };
  };
}
