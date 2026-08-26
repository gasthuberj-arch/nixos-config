{pkgs, ...}: {
  # Server Profile: Power management and headless operation

  # Disable sleep / suspend targets
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Enable Wake-on-LAN for all ethernet interfaces
  systemd.services.enable-wol = {
    description = "Enable Wake-on-LAN on all ethernet interfaces";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for interface in $(${pkgs.iproute2}/bin/ip -o link show | ${pkgs.gnugrep}/bin/grep -v 'link/loopback' | ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | ${pkgs.gnused}/bin/sed 's/@.*//'); do
        if ${pkgs.ethtool}/bin/ethtool "$interface" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Supports Wake-on"; then
          echo "Enabling Wake-on-LAN for $interface"
          ${pkgs.ethtool}/bin/ethtool -s "$interface" wol g || true
        fi
      done
    '';
  };

  # Mesh VPN
  services.tailscale.enable = true;
}
