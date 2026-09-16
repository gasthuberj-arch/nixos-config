{
  config,
  pkgs,
  pkgs-unstable,
  ...
}: let
  # intune-agent's compliance check parses this line directly out of
  # whichever of these three distro-conventional PAM files exists.
  pwqualityCheckLine = "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so retry=3 minlen=8 enforce_for_root";
in {
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/core/base.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/greetd.nix
  ];

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;
  # IPv6 here is local-only (ULA, no default route) but DNS still returns
  # public AAAA records, so apps without Happy-Eyeballs fallback (e.g.
  # intune-portal's HTTP client) fail outright instead of trying IPv4.
  networking.enableIPv6 = false;
  networking.networkmanager.dns = "dnsmasq"; # NM runs its own local dnsmasq resolver

  environment.etc."NetworkManager/dnsmasq.d/qualitatio-wildcard.conf".text = ''
    address=/qualitatio.test/192.168.122.141
  '';

  boot.kernelParams = ["amd_pstate=active"];

  # Hardware & Firmware support for modern notebooks
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Trash/mount/network-share backend Thunar needs for real copy-paste
  # (without it, cut/paste and the trash can silently no-op).
  services.gvfs.enable = true;

  # The native 3.0.1 microsoft-identity-broker (current nixpkgs default)
  # can't complete interactive sign-in here; pin back to the last
  # Java-based release. See pkgs/microsoft-identity-broker-2.0.1.nix.
  nixpkgs.overlays = [
    (final: prev: {
      microsoft-identity-broker = final.callPackage ../../pkgs/microsoft-identity-broker-2.0.1.nix {};
    })
  ];

  services.intune.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Intune compliance policy requires a minimum password length (8). The
  # intune-agent binary (verified via `strings`) checks this by directly
  # parsing a pam_pwquality "minlen=" argument out of one of three
  # distro-conventional PAM include files: /etc/pam.d/common-password
  # (Debian/Ubuntu), /etc/pam.d/system-password, or /etc/pam.d/password-auth
  # (RHEL/Fedora). None of these exist on NixOS (services have their own
  # independent PAM stacks, no shared include), so the compliance check
  # sees actual_value=0 regardless of what's actually enforced. These
  # files aren't included by any real PAM stack here — they only need to
  # exist with the right content for the checker to find.
  environment.etc."pam.d/common-password".text = pwqualityCheckLine;
  environment.etc."pam.d/system-password".text = pwqualityCheckLine;
  environment.etc."pam.d/password-auth".text = pwqualityCheckLine;

  security.pam.services.passwd.rules.password.pwquality = {
    control = "requisite";
    modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
    order = config.security.pam.services.passwd.rules.password.unix.order - 10;
    settings = {
      retry = 3;
      minlen = 8;
      enforce_for_root = true;
    };
  };

  # k3s/Longhorn now live in libvirt VMs instead of bare metal — NixOS's
  # non-FHS layout fights Longhorn's hardcoded /usr/bin path assumptions,
  # and a real guest kernel avoids that class of problem entirely.
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  environment.systemPackages = with pkgs; [
    virt-viewer
    cloud-utils
  ];

  # Container Runtime (Docker daemon for standard dev & test workflows)
  virtualisation.docker = {
    enable = true;
    package = pkgs-unstable.docker;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Binary compatibility for prebuilt binaries (e.g. agy, VS Code remote, language servers,
  # Playwright's downloaded Chromium)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    libseccomp

    # Playwright/Chromium runtime deps
    glib
    nss
    nspr
    at-spi2-atk
    cups
    dbus
    expat
    mesa
    cairo
    pango
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    libxkbcommon
    alsa-lib
    libgbm
  ];

  # Bootloader: systemd-boot with portable fallback executable
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${pkgs.coreutils}/bin/mkdir -p /boot/EFI/BOOT
    ${pkgs.coreutils}/bin/cp -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI || true
  '';
  boot.loader.efi.canTouchEfiVariables = true;

  # System fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ];

  # User account configuration
  users.users.johannes = {
    extraGroups = ["networkmanager" "wheel" "video" "render" "input" "docker" "libvirtd"];
    shell = pkgs.zsh;
  };

  # Enable zsh system-wide as login shell for johannes
  programs.zsh.enable = true;

  # System state version
  system.stateVersion = "25.11";
}
