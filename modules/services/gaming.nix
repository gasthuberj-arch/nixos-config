{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming;
in {
  options.services.gaming = {
    enable = mkEnableOption "gaming services and emulators";

    sunshine = {
      enable = mkEnableOption "Sunshine game streaming server";
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open firewall ports for Sunshine";
      };
    };

    emulators = {
      enable = mkEnableOption "gaming emulators";

      retroarch = mkOption {
        type = types.bool;
        default = true;
        description = "Install RetroArch (multi-system emulator)";
      };

      dolphin = mkOption {
        type = types.bool;
        default = true;
        description = "Install Dolphin (GameCube/Wii emulator)";
      };

      pcsx2 = mkOption {
        type = types.bool;
        default = true;
        description = "Install PCSX2 (PlayStation 2 emulator)";
      };

      rpcs3 = mkOption {
        type = types.bool;
        default = true;
        description = "Install RPCS3 (PlayStation 3 emulator)";
      };

      duckstation = mkOption {
        type = types.bool;
        default = false;
        description = "Install DuckStation (PlayStation 1 emulator) - requires accepting non-commercial license";
      };

      cemu = mkOption {
        type = types.bool;
        default = true;
        description = "Install Cemu (Wii U emulator)";
      };

      ryubing = mkOption {
        type = types.bool;
        default = true;
        description = "Install Ryubing (Nintendo Switch emulator, formerly Ryujinx)";
      };

      ppsspp = mkOption {
        type = types.bool;
        default = true;
        description = "Install PPSSPP (PSP emulator)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Sunshine game streaming configuration
    services.sunshine = mkIf cfg.sunshine.enable {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = cfg.sunshine.openFirewall;
    };

    # Set Wayland environment for Sunshine user service
    systemd.user.services.sunshine = mkIf cfg.sunshine.enable {
      serviceConfig = {
        Environment = [
          "WAYLAND_DISPLAY=wayland-0"
        ];
      };
    };

    # Firewall configuration for Sunshine
    networking.firewall = mkIf (cfg.sunshine.enable && cfg.sunshine.openFirewall) {
      allowedTCPPorts = [
        47984 # HTTPS Web UI
        47989 # HTTP Web UI
        47990 # RTSP
        48010 # Video stream
      ];
      allowedUDPPorts = [
        47998 # Video
        47999 # Control
        48000 # Audio
        48002 # Control
        48010 # Video stream
      ];
    };

    # Install emulators based on configuration
    environment.systemPackages = with pkgs;
      (optional cfg.sunshine.enable sunshine)
      ++ (optionals cfg.emulators.enable (
        (optional cfg.emulators.retroarch retroarch)
        ++ (optional cfg.emulators.dolphin dolphin-emu)
        ++ (optional cfg.emulators.pcsx2 pcsx2)
        ++ (optional cfg.emulators.rpcs3 rpcs3)
        ++ (optional cfg.emulators.duckstation duckstation)
        ++ (optional cfg.emulators.cemu cemu)
        ++ (optional cfg.emulators.ryubing ryubing)
        ++ (optional cfg.emulators.ppsspp ppsspp-qt)
      ));

    # Enable OpenGL and Vulkan support for gaming
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # Enable gamemode for performance optimization
    programs.gamemode.enable = mkIf cfg.emulators.enable true;

    # Persist Sunshine configuration and emulator data
    environment.persistence."/persist" = {
      directories = mkIf cfg.sunshine.enable [
        "/var/lib/sunshine"
      ];

      users.johannes.directories = mkIf cfg.emulators.enable [
        ".config/retroarch"
        ".config/dolphin-emu"
        ".config/PCSX2"
        ".config/rpcs3"
        ".config/duckstation"
        ".config/Cemu"
        ".config/Ryubing"
        ".config/ppsspp"
        # Save data directories
        ".local/share/dolphin-emu"
        ".local/share/PCSX2"
        ".local/share/rpcs3"
        ".local/share/duckstation"
        ".local/share/Ryubing"
      ];
    };
  };
}
