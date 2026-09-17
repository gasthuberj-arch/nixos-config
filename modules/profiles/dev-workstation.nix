{
  pkgs,
  pkgs-unstable,
  ...
}: {
  # k3s/Longhorn now live in libvirt VMs instead of bare metal — NixOS's
  # non-FHS layout fights Longhorn's hardcoded /usr/bin path assumptions,
  # and a real guest kernel avoids that class of problem entirely.
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  environment.systemPackages = with pkgs; [
    virt-viewer
    cloud-utils
  ];

  # Container Runtime (Docker daemon for standard dev & test workflows)
  virtualisation.docker = {
    enable = true;
    package = pkgs-unstable.docker;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Binary compatibility for prebuilt binaries (e.g. agy, VS Code remote, language servers,
  # Playwright's downloaded Chromium)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    libseccomp

    # Playwright/Chromium runtime deps
    glib
    nss
    nspr
    at-spi2-atk
    cups
    dbus
    expat
    mesa
    cairo
    pango
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    libxkbcommon
    alsa-lib
    libgbm
  ];

  # System fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ];
}
