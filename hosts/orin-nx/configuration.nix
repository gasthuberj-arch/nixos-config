{pkgs, ...}: {
  imports = [
    # Universal baseline
    ../../modules/core/base.nix
  ];

  nixpkgs.overlays = [
    (_final: prev: {
      pythonPackagesExtensions =
        prev.pythonPackagesExtensions
        ++ [
          (_pyFinal: pyPrev: {
            pygount = pyPrev.pygount.overridePythonAttrs (_old: {
              dontCheckRuntimeDeps = true;
            });
          })
        ];
      nvidia-jetpack6 = prev.nvidia-jetpack6.overrideScope (_jFinal: jPrev: {
        jetsonStandaloneMMOptee = jPrev.jetsonStandaloneMMOptee.overrideAttrs (_old: {
          buildPhase = ''
            export PYTHONPATH="$(find /nix/store -maxdepth 4 -name 'pkg_resources' 2>/dev/null | head -n 1 | xargs -r dirname):$PYTHONPATH"
            python3 -c "import sys; print('Available sys.path:', sys.path)"
            python3 -c "import setuptools; import pkg_resources; print('pkg_resources FOUND at', pkg_resources.__file__)"
            stuart_setup -c "edk2-nvidia/Platform/NVIDIA/StandaloneMmOptee/PlatformBuild.py"
            stuart_build -c "edk2-nvidia/Platform/NVIDIA/StandaloneMmOptee/PlatformBuild.py" --target RELEASE
          '';
        });
      });
    })
  ];

  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-nx";
    carrierBoard = "devkit";
  };

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
    extraConfig = ''
      set root=(hd0,gpt1)
    '';
  };
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = false;

  # NVMe storage configuration for root and EFI boot filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/APP";
    fsType = "ext4";
    autoResize = true;
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-partlabel/esp";
    fsType = "vfat";
  };

  # Networking & Tailscale
  networking.hostName = "orin-nx";
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;

  # Dual-homed network configuration (Prevents ARP Flux & Asymmetric Routing drops on same subnet)
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.default.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_announce" = 2;
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
  };

  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "dual-homed-routing" ''
        IFACE="$1"
        ACTION="$2"
        if [ "$IFACE" = "enP1p1s0" ] && [ "$ACTION" = "up" ]; then
          IP="$DHCP4_IP_ADDRESS"
          ROUTER="$DHCP4_ROUTERS"
          if [ -n "$IP" ] && [ -n "$ROUTER" ]; then
            ip route replace default via "$ROUTER" dev "$IFACE" table 100
            ip rule del from "$IP" table 100 2>/dev/null || true
            ip rule add from "$IP" table 100 priority 100
          fi
        fi
      '';
      type = "basic";
    }
  ];

  # LLM utilities
  services.ollama = {
    enable = true;
  };

  # Enable nix-ld to execute dynamically linked binaries from uv/pip/npm
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    uv
    python3
    llama-cpp
  ];

  # High Performance Mode (All 8 CPU Cores @ 2.0 GHz, Performance Governor)
  systemd.services.jetson-performance-mode = {
    description = "Enable Jetson MAXN Uncapped Performance Mode on Boot";
    wantedBy = ["multi-user.target"];
    after = ["nvpmodel.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "enable-maxn-performance" ''
        for i in 0 1 2 3 4 5 6 7; do
          echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null || true
        done
        for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          echo performance > $g 2>/dev/null || true
        done
        for g in /sys/devices/platform/17000000.gpu/devfreq_dev/governor /sys/devices/17000000.gpu/devfreq/*/governor; do
          echo performance > $g 2>/dev/null || true
        done
      '';
    };
  };

  system.stateVersion = "24.11";
}
