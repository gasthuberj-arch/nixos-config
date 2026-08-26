{
  config,
  lib,
  inputs,
  ...
}: {
  imports = [
    # System core baseline & profiles
    ../../modules/core/base.nix
    ../../modules/profiles/server.nix
    ../../modules/profiles/desktop.nix

    # Storage & Root modules
    ../../modules/zfs-root.nix
    ./hardware-configuration.nix
    ./disko-config.nix
    ./persistence.nix
    "${inputs.impermanence}/nixos.nix"

    # Application service modules
    ../../modules/services/caddy.nix
    ../../modules/services/authelia.nix
    ../../modules/services/immich.nix
    ../../modules/services/paperless.nix
    ../../modules/services/nextcloud.nix
    ../../modules/services/homeassistant.nix
    ../../modules/services/grafana.nix
    ../../modules/services/gaming.nix
    ../../modules/services/obsidian-sync.nix
    ../../modules/services/hdd-spindown.nix
  ];

  # --- ZFS Boot & Pool Hardware Configuration ---
  zfs-root = {
    bootDevices = [
      "nvme-eui.e8238fa6bf530001001b444a41dec6c0" # WD Blue SN580 1TB
      "nvme-eui.0000000624098582caf25b0310000218" # Lexar SSD NM790 1TB
    ];
    sataDevices = [
      "wwn-0x5000c500e9cad552" # ST4000VN006 - sda
      "wwn-0x5000c500e9cb50d6" # ST4000VN006 - sdb
      "wwn-0x5000c500e99f1472" # ST4000VN006 - sdc
    ];
  };

  # Bootloader - Mirrored EFI configuration
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efis/nvme-eui.e8238fa6bf530001001b444a41dec6c0-part2";
  boot.loader.systemd-boot.enable = true;
  boot.loader.grub.efiInstallAsRemovable = lib.mkForce false;
  boot.loader.grub.mirroredBoots = [
    {
      devices = ["nodev"];
      path = "/boot/efis/nvme-eui.0000000624098582caf25b0310000218-part2";
    }
  ];

  # ZFS filesystems & maintenance
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "8425e349";

  # Rollback root filesystem on boot (impermanence)
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/nixos/empty@start
  '';

  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "monthly";
  services.zfs.trim.enable = true;

  # Filesystem mount options
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/lib".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  fileSystems."/media".options = ["nofail" "x-systemd.after=zfs-import.target"];
  fileSystems."/pictures".options = ["nofail" "x-systemd.after=zfs-import.target"];
  fileSystems."/archive".options = ["nofail" "x-systemd.after=zfs-import.target"];
  fileSystems."/backups".options = ["nofail" "x-systemd.after=zfs-import.target"];

  # --- Virtual Input Devices (Sunshine Game Streaming) ---
  boot.kernelModules = ["uinput"];
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", GROUP="input", MODE="0660"
  '';

  # --- Networking & Host Identification ---
  networking.hostName = "homelab";
  networking.networkmanager.enable = true;
  networking.hosts = {
    "127.0.0.1" = [
      "homelab.lan"
      "auth.homelab.lan"
      "immich.homelab.lan"
      "paperless.homelab.lan"
      "nextcloud.homelab.lan"
      "homeassistant.homelab.lan"
      "grafana.homelab.lan"
      "obsidian.homelab.lan"
    ];
  };

  # --- Declarative Homelab Application Services ---
  homelab.services = {
    # Caddy reverse proxy engine
    caddy = {
      enable = true;
      domain = "homelab.lan";
    };

    # Authelia SSO
    authelia = {
      enable = true;
      domain = "homelab.lan";
    };

    # Immich photo management
    immich = {
      enable = true;
      port = 2283;
      mediaLocation = "/pictures/immich";
    };

    # Paperless-ngx document management
    paperless = {
      enable = true;
      port = 28981;
    };

    # Nextcloud self-hosted cloud
    nextcloud = {
      enable = true;
      hostName = "nextcloud.homelab.lan";
      maxUploadSize = "16G";
    };

    # Obsidian LiveSync
    obsidian-sync = {
      enable = true;
      port = 5984;
    };

    # Automatic HDD Spindown for SATA RAIDZ1 cold storage
    hdd-spindown = {
      enable = true;
      devices = config.zfs-root.sataDevices;
      spindownTimeout = 180; # 15 minutes
    };

    # Home Assistant home automation
    homeassistant = {
      enable = true;
      port = 8123;
    };

    # Grafana monitoring stack
    grafana = {
      enable = true;
      port = 3000;
      prometheus = {
        enable = true;
        port = 9090;
        retentionTime = "365d";
      };
      loki = {
        enable = true;
        port = 3100;
      };
      exporters = {
        node = true;
        systemd = true;
        zfs = true;
      };
    };

    # Gaming services and emulators
    gaming = {
      enable = true;
      sunshine = {
        enable = true;
        openFirewall = true;
      };
      emulators = {
        enable = true;
        retroarch = true;
        dolphin = true;
        pcsx2 = true;
        rpcs3 = true;
        duckstation = false;
        cemu = true;
        ryubing = true;
        ppsspp = true;
      };
    };
  };

  # State version
  system.stateVersion = "24.11";
}
