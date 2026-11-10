{
  pkgs,
  lib,
  config,
  ...
}: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # No --remember-user-session: a remembered menu pick (e.g. plain
        # "Hyprland") silently overrides --cmd, so the session skips UWSM,
        # graphical-session.target never starts, and units hanging off it
        # (intune-agent.timer -> Intune compliance check-in) never run.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd '${lib.getExe config.programs.uwsm.package} start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  # Fix for tuigreet screen flicker / tty issues
  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal";
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };
}
