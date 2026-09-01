{
  pkgs,
  lib,
  ...
}: {
  # Desktop Profile: GNOME, Display Manager, Audio, and Display power inhibitors

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable GNOME & GDM with autologin
  services.displayManager.gdm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "johannes";
  };
  services.desktopManager.gnome.enable = true;

  # Workaround for GDM autologin bug
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS printing
  services.printing.enable = true;

  # Enable Sound with PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Prevent GNOME from suspending on idle
  services.displayManager.gdm.autoSuspend = false;

  # Disable GNOME screen blanking and power management
  services.xserver.displayManager.sessionCommands = ''
    ${pkgs.xorg.xset}/bin/xset s off
    ${pkgs.xorg.xset}/bin/xset -dpms
    ${pkgs.xorg.xset}/bin/xset s noblank
  '';

  # GNOME settings to prevent screen from turning off
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/session" = {
          idle-delay = lib.gvariant.mkUint32 0; # Never go idle
        };
        "org/gnome/desktop/screensaver" = {
          lock-enabled = false;
          idle-activation-enabled = false;
        };
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
          idle-dim = false;
        };
      };
    }
  ];
}
