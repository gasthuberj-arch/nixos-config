{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../../modules/zfs-root.nix
    ../../modules/services/caddy.nix
    ../../modules/services/authelia.nix
    ../../modules/services/immich.nix
    ../../modules/services/paperless.nix
    ../../modules/services/nextcloud.nix
    ../../modules/services/homeassistant.nix
    ../../modules/services/grafana.nix
    ../../modules/services/gaming.nix
    ./hardware-configuration.nix
    ./disko-config.nix
    "${inputs.impermanence}/nixos.nix"
  ];

  # ZFS boot device configuration
  zfs-root = {
    bootDevices = [
      "nvme-eui.e8238fa6bf530001001b444a41dec6c0"  # WD Blue SN580 1TB
      "nvme-eui.0000000624098582caf25b0310000218"  # Lexar SSD NM790 1TB
    ];
    sataDevices = [
      "wwn-0x5000c500e9cad552"  # ST4000VN006 - sda
      "wwn-0x5000c500e9cb50d6"  # ST4000VN006 - sdb
      "wwn-0x5000c500e99f1472"  # ST4000VN006 - sdc
    ];
  };

  # Bootloader - mirrored EFI configuration
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efis/nvme-eui.e8238fa6bf530001001b444a41dec6c0-part2";
  boot.loader.systemd-boot.enable = true;

  # Mirror EFI partitions
  boot.loader.grub.efiInstallAsRemovable = lib.mkForce false;
  boot.loader.grub.mirroredBoots = [
    {
      devices = [ "nodev" ];
      path = "/boot/efis/nvme-eui.0000000624098582caf25b0310000218-part2";
    }
  ];

  # ZFS configuration
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "8425e349"; # Required for ZFS

  # Load uinput kernel module for Sunshine virtual input devices
  boot.kernelModules = [ "uinput" ];

  # Set uinput permissions
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", GROUP="input", MODE="0660"
  '';

  # Rollback root filesystem on boot (impermanence)
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/nixos/empty@start
  '';

  # ZFS services
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "monthly";
  services.zfs.trim.enable = true;

  # Add neededForBoot flag to /persist for impermanence
  fileSystems."/persist" = {
    neededForBoot = true;
  };

  # Add nofail option to SATA pool mounts to prevent boot blocking
  fileSystems."/media" = {
    options = [ "nofail" "x-systemd.after=zfs-import.target" ];
  };

  fileSystems."/pictures" = {
    options = [ "nofail" "x-systemd.after=zfs-import.target" ];
  };

  fileSystems."/archive" = {
    options = [ "nofail" "x-systemd.after=zfs-import.target" ];
  };

  fileSystems."/backups" = {
    options = [ "nofail" "x-systemd.after=zfs-import.target" ];
  };

  # Impermanence - persist important files across reboots
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # Note: /var/log and /var/lib have dedicated ZFS datasets mounted directly
      # Only persist specific subdirectories of /var/lib that need persistence
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

  # Hostname
  networking.hostName = "homelab";

  # Local hostname resolution for Caddy virtual hosts
  networking.hosts = {
    "127.0.0.1" = [
      "homelab.lan"
      "auth.homelab.lan"
      "immich.homelab.lan"
      "paperless.homelab.lan"
      "nextcloud.homelab.lan"
      "homeassistant.homelab.lan"
      "grafana.homelab.lan"
    ];
  };

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable Wake-on-LAN for all ethernet interfaces
  systemd.services.enable-wol = {
    description = "Enable Wake-on-LAN on all ethernet interfaces";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Enable WoL on all ethernet interfaces
      for interface in $(${pkgs.iproute2}/bin/ip -o link show | ${pkgs.gnugrep}/bin/grep -v 'link/loopback' | ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | ${pkgs.gnused}/bin/sed 's/@.*//'); do
        if ${pkgs.ethtool}/bin/ethtool "$interface" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Supports Wake-on"; then
          echo "Enabling Wake-on-LAN for $interface"
          ${pkgs.ethtool}/bin/ethtool -s "$interface" wol g || true
        fi
      done
    '';
  };

  # Set your time zone
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "johannes";
  };
  services.desktopManager.gnome.enable = true;

  # Workaround for GDM autologin bug
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Disable automatic suspension
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Prevent GNOME from suspending on idle
  services.displayManager.gdm.autoSuspend = false;

  # Disable GNOME screen blanking and power management
  services.xserver.displayManager.sessionCommands = ''
    # Disable screen blanking
    ${pkgs.xorg.xset}/bin/xset s off
    ${pkgs.xorg.xset}/bin/xset -dpms
    ${pkgs.xorg.xset}/bin/xset s noblank
  '';

  # GNOME settings to prevent screen from turning off
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/desktop/session" = {
        idle-delay = lib.gvariant.mkUint32 0;  # Never go idle
      };
      "org/gnome/desktop/screensaver" = {
        lock-enabled = false;
        idle-activation-enabled = false;
      };
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing";
        idle-dim = false;
      };
    };
  }];

  # User account
  users.users.johannes = {
    isNormalUser = true;
    description = "Johannes Gasthuber";
    extraGroups = [ "networkmanager" "wheel" "video" "render" "input" ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEKnd5qMAsokd5qJ5ont28fwQVSNcQJ92mOm60pAf+/ johannes@laptop"
    ];
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Tailscale
  services.tailscale.enable = true;

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ]; # Additional ports opened by services

  # Caddy reverse proxy
  services.caddy-custom = {
    enable = true;
    domain = "homelab.lan";
    # email = "your-email@example.com"; # Uncomment for Let's Encrypt certs
  };

  # Authelia SSO
  services.authelia-custom = {
    enable = true;
    domain = "homelab.lan";
  };

  # Immich photo management
  services.immich-custom = {
    enable = true;
    port = 2283;
    mediaLocation = "/pictures/immich";
  };

  # Paperless-ngx document management
  services.paperless-custom = {
    enable = true;
    port = 28981;
    # dataDir defaults to /var/lib/paperless (will be persisted)
  };

  # Nextcloud self-hosted cloud
  services.nextcloud-custom = {
    enable = true;
    hostName = "nextcloud.homelab.lan";
    maxUploadSize = "16G";
    # dataDir defaults to /var/lib/nextcloud (will be persisted)
  };

  # Home Assistant home automation
  services.homeassistant-custom = {
    enable = true;
    port = 8123;
    # dataDir defaults to /var/lib/hass (will be persisted)
  };

  # Grafana monitoring stack
  services.grafana-custom = {
    enable = true;
    port = 3000;

    # Prometheus metrics collection
    prometheus = {
      enable = true;
      port = 9090;
      retentionTime = "365d";  # Keep metrics for 1 year
    };

    # Loki log aggregation
    loki = {
      enable = true;
      port = 3100;
    };

    # Exporters for system monitoring
    exporters = {
      node = true;      # System metrics (CPU, memory, disk, etc.)
      systemd = true;   # Systemd service metrics
      zfs = true;       # ZFS pool metrics
    };
  };

  # Gaming services and emulators
  services.gaming = {
    enable = true;

    # Sunshine game streaming
    sunshine = {
      enable = true;
      openFirewall = true;
    };

    # Emulators
    emulators = {
      enable = true;
      retroarch = true;    # Multi-system emulator
      dolphin = true;      # GameCube/Wii
      pcsx2 = true;        # PlayStation 2
      rpcs3 = true;        # PlayStation 3
      duckstation = false; # PlayStation 1 (disabled by default due to non-commercial license)
      cemu = true;         # Wii U
      ryubing = true;      # Nintendo Switch
      ppsspp = true;       # PSP
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    htop
    tmux
    zfs
    ethtool  # For Wake-on-LAN configuration
    tailscale
  ];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "25.11";
}
