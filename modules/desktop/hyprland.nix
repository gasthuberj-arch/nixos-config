{pkgs, ...}: {
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  # Wayland / desktop integration essentials
  security.polkit.enable = true;
  security.pam.services.hyprlock = {};

  # Portals for screen sharing, file pickers, etc.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
  };

  # dconf backs the GTK/libadwaita "prefer-dark" setting that
  # xdg-desktop-portal-gtk exposes over the freedesktop Settings portal.
  # Without the dconf daemon, `gsettings set` (used by theme-toggle) has
  # nowhere to persist the value and silently fails.
  programs.dconf.enable = true;

  # gsettings-desktop-schemas ships its (already-compiled) schemas under
  # share/gsettings-schemas/<name>/glib-2.0/ specifically so multiple
  # schema-providing packages don't collide when buildEnv merges
  # environment.systemPackages - nothing recompiles/re-links them into
  # /run/current-system/sw. Without this on XDG_DATA_DIRS, `gsettings`
  # fails with "No schemas installed" even with the package installed.
  environment.sessionVariables.XDG_DATA_DIRS = ["${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"];

  # Pipewire audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Power management on laptop
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # System packages useful in Hyprland
  environment.systemPackages = with pkgs; [
    kitty
    foot
    waybar
    wofi
    dunst
    libnotify
    wl-clipboard
    brightnessctl
    pavucontrol
    networkmanagerapplet
    hyprpaper
    hyprlock
    hypridle
    grim
    slurp
    glib # gsettings CLI, used by theme-toggle for the GTK dark/light portal setting
    gsettings-desktop-schemas # org.gnome.desktop.interface etc. - gsettings has nothing to read/write without these
  ];
}
