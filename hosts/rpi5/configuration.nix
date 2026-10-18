{
  nixos-raspberrypi,
  pkgs,
  ...
}: {
  imports = [
    # Universal baseline
    ../../modules/core/base.nix

    # Raspberry Pi 5 kernel & hardware modules
    nixos-raspberrypi.nixosModules.sd-image
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
  ];

  networking.hostName = "rpi5";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = ["tailscale0"];

  # Mesh VPN
  services.tailscale.enable = true;

  # Moonlight client & game controller support for living room streaming
  environment.systemPackages = with pkgs; [
    moonlight-qt
  ];
  services.udev.packages = [pkgs.game-devices-udev-rules];

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.11";
}
