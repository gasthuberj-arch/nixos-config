{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/core/base.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/greetd.nix
  ];

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

  # Bootloader: systemd-boot for UEFI with LUKS prompt
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable zsh system-wide as login shell for johannes
  programs.zsh.enable = true;
  users.users.johannes.shell = pkgs.zsh;

  # System state version
  system.stateVersion = "25.11";
}
