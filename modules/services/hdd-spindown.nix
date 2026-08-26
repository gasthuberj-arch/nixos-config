{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.hdd-spindown;
in {
  options.services.hdd-spindown = {
    enable = mkEnableOption "Automatic HDD standby spindown";

    devices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of disk-by-id names to manage (relative to /dev/disk/by-id/ or absolute paths)";
    };

    spindownTimeout = mkOption {
      type = types.int;
      default = 180; # 180 * 5s = 15 minutes (120=10min, 180=15min, 240=20min, 241=30min)
      description = "hdparm -S timeout value (180 = 15 minutes)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.hdparm];

    systemd.services.hdd-spindown = {
      description = "Configure HDD Spindown Timeouts";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for dev_name in ${toString cfg.devices}; do
          if [[ "$dev_name" == /* ]]; then
            dev="$dev_name"
          else
            dev="/dev/disk/by-id/$dev_name"
          fi

          if [ -b "$dev" ]; then
            echo "Setting spindown timeout (value: ${toString cfg.spindownTimeout}) on $dev..."
            ${pkgs.hdparm}/bin/hdparm -S ${toString cfg.spindownTimeout} "$dev" || true
            ${pkgs.hdparm}/bin/hdparm -B 127 "$dev" 2>/dev/null || true
          else
            echo "Device $dev not found, skipping"
          fi
        done
      '';
    };
  };
}
