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

  # Bootloader: systemd-boot for UEFI with LUKS prompt
  boot.loader.systemd-boot.enable = true;
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
    extraGroups = ["networkmanager" "wheel" "video" "render" "input" "docker"];
    shell = pkgs.zsh;
  };

  # Enable zsh system-wide as login shell for johannes
  programs.zsh.enable = true;

  # System state version
  system.stateVersion = "25.11";
}
