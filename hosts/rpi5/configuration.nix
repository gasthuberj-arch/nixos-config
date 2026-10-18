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

  # Hardware acceleration, bluetooth & audio
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Sound with PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Standalone emulators, frontend & Moonlight client
  environment.systemPackages = with pkgs; [
    retroarch
    dolphin-emu
    ppsspp
    pegasus-frontend
    moonlight-qt
  ];
  services.udev.packages = [pkgs.game-devices-udev-rules];

  system.stateVersion = "25.11";
}
