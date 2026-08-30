{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.gaming;

  # Helper to reduce repetition for emulator options
  mkEmulator = name: desc: {
    inherit name;
    value = mkOption {
      type = types.bool;
      default = true;
      description = desc;
    };
  };
in {
  options.homelab.services.gaming = {
    enable = mkEnableOption "gaming services and emulators";

    user = mkOption {
      type = types.str;
      default = "johannes";
      description = "The user for gaming persistence and services";
    };

    sunshine = {
      enable = mkEnableOption "Sunshine game streaming server";

      openFirewall = mkOption {
        type = types.bool;
        default = false; # Default to FALSE for security (Rely on Tailscale)
        description = "Open ports on the physical LAN. Keep false if using Tailscale.";
      };

      lockOnBoot = mkOption {
        type = types.bool;
        default = true;
        description = "Immediately lock the screen after auto-login to secure physical access.";
      };
    };

    emulators = {
      enable = mkEnableOption "gaming emulators";
      # Generate options using the helper
      retroarch = (mkEmulator "retroarch" "Multi-system emulator").value;
      dolphin = (mkEmulator "dolphin" "GameCube/Wii emulator").value;
      pcsx2 = (mkEmulator "pcsx2" "PS2 emulator").value;
      rpcs3 = (mkEmulator "rpcs3" "PS3 emulator").value;
      cemu = (mkEmulator "cemu" "Wii U emulator").value;
      ryubing = (mkEmulator "ryubing" "Switch emulator (Ryubing)").value;
      ppsspp = (mkEmulator "ppsspp" "PSP emulator").value;

      duckstation = mkOption {
        type = types.bool;
        default = false;
        description = "PS1 emulator (Non-commercial license)";
      };
    };
  };

  config = mkIf cfg.enable {
    # --- Security: Firewall & Networking ---

    # 1. Trust Tailscale implicitly
    # This allows Sunshine to work perfectly over Tailscale without opening LAN ports.
    networking.firewall.trustedInterfaces = ["tailscale0"];

    # This mitigates the risk of "Auto Login". The user is logged in (so Sunshine starts),
    # but the screen is immediately locked so nobody can physically use the PC.
    systemd.user.services.secure-gaming-lock = mkIf (cfg.sunshine.enable && cfg.sunshine.lockOnBoot) {
      description = "Lock screen immediately for secure auto-login";
      after = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/loginctl lock-session";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      wantedBy = ["graphical-session.target"];
    };

    # --- Sunshine Service Configuration ---

    services.sunshine = mkIf cfg.sunshine.enable {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = false; # Handled manually above
    };

    # Fix Wayland environment for Sunshine
    systemd.user.services.sunshine = mkIf cfg.sunshine.enable {
      serviceConfig.Environment = ["WAYLAND_DISPLAY=wayland-0"];
    };

    # --- Packages & Emulators ---

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

    # --- Hardware & Performance ---

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    programs.gamemode.enable = mkIf cfg.emulators.enable true;
  };
}
