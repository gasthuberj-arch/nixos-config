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
      "/var/lib/vaultwarden"
      "/var/lib/postgresql"
      "/var/lib/redis-immich"
      "/var/lib/redis-paperless"
      "/var/lib/redis-nextcloud"
      "/var/lib/sunshine"
      "/var/lib/gatus"
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

  # Prevent impermanence from unmounting persistent files during live rebuild switches.
  # Unmounting /etc/machine-id kills dbus-broker, which freezes switch-to-configuration
  # in an infinite DBus loop and prevents services (Immich, Paperless, etc.) from restarting.
  systemd.services = {
    "persist-persist-etc-machine\\x2did" = {
      stopIfChanged = false;
      restartIfChanged = false;
    };
    "persist-persist-etc-ssh-ssh_host_ed25519_key" = {
      stopIfChanged = false;
      restartIfChanged = false;
    };
    "persist-persist-etc-ssh-ssh_host_ed25519_key.pub" = {
      stopIfChanged = false;
      restartIfChanged = false;
    };
    "persist-persist-etc-ssh-ssh_host_rsa_key" = {
      stopIfChanged = false;
      restartIfChanged = false;
    };
    "persist-persist-etc-ssh-ssh_host_rsa_key.pub" = {
      stopIfChanged = false;
      restartIfChanged = false;
    };

    # systemd-machine-id-commit fails on impermanence because /etc/machine-id is
    # already a persistent bind mount ("not on a temporary file system").
    systemd-machine-id-commit.enable = false;
  };
}
