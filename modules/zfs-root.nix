{lib, ...}: {
  options.zfs-root = {
    bootDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of boot device IDs (by-id names without /dev/disk/by-id/ prefix) for ZFS mirrored boot/root pools";
      example = ["nvme-eui.001234567890abcd" "nvme-eui.fedcba0987654321"];
    };

    sataDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of SATA device IDs (by-id names without /dev/disk/by-id/ prefix) for ZFS RAIDZ cold storage pool";
      example = ["wwn-0x5000c500e9cad552" "wwn-0x5000c500e9cb50d6" "wwn-0x5000c500e99f1472"];
    };
  };
}
