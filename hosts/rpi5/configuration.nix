{
  config,
  lib,
  nixos-raspberrypi,
  ...
}: {
  imports = [
    nixos-raspberrypi.nixosModules.sd-image
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
  ];

  networking.hostName = "rpi5";
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader.raspberryPi = {
    enable = true;
    # version = 5;
    bootloader = "kernel";
  };

  hardware.enableRedistributableFirmware = true;

  services.openssh.enable = true;

  users.users.johannes = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    # Add SSH keys or a password before first boot.
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.11";
}
