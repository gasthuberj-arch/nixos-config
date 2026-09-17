{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/core/base.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/greetd.nix
    ../../modules/profiles/dev-workstation.nix
    ../../modules/profiles/work.nix
  ];

  networking.hostName = "work-laptop";
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

  # Trash/mount/network-share backend Thunar needs for real copy-paste
  # (without it, cut/paste and the trash can silently no-op).
  services.gvfs.enable = true;

  # Bootloader: systemd-boot with portable fallback executable
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${pkgs.coreutils}/bin/mkdir -p /boot/EFI/BOOT
    ${pkgs.coreutils}/bin/cp -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI || true
  '';
  boot.loader.efi.canTouchEfiVariables = true;

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
