# PLACEHOLDER — this machine hasn't been installed yet.
#
# Replace this whole file by running `nixos-generate-config` on the real
# hardware once you're ready to install (it will detect the actual disk
# controllers, GPU, and CPU microcode needed). Until then this is just
# enough for `nix flake check` to evaluate the personal-laptop config.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
