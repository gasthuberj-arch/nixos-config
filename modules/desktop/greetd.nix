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
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --cmd '${lib.getExe config.programs.uwsm.package} start hyprland-uwsm.desktop'";
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
