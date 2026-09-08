{
  pkgs,
  pkgs-unstable,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/core/base.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/greetd.nix
  ];

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

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

  services.intune.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

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

  # Binary compatibility for prebuilt binaries (e.g. agy, VS Code remote, language servers)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    libseccomp
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
