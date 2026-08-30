{pkgs, ...}: {
  # Nix & Flake settings
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
      trusted-users = ["root" "@wheel"];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # ZFS root import behavior
  boot.zfs.forceImportRoot = false;

  # Time and Locale settings
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Primary system user
  users.users.johannes = {
    isNormalUser = true;
    description = "Johannes Gasthuber";
    extraGroups = ["networkmanager" "wheel" "video" "render" "input"];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDumbQq8XRp8wsmWRp2sPxZJNvfAvgi8NTFmBCfUpmZ6 johannes@pop-os"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEKnd5qMAsokd5qJ5ont28fwQVSNcQJ92mOm60pAf+/ johannes@laptop"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0TsfKFP+0G6y3XdH31d9b92DIlw/xzozb8wBowwucy9DBPgtS0pBKFxhjnO3rcx7g6Z1ARKUNyjd0aGqUjc253v6nedakFfR0QEhEiNVTCg3I4RwP2JQ57hzoGPA9WmHgN/z0KD/lgFdQ5vytvHwoK8ig1U884qPnx029WgzzCaVGHiTf6xtSXVQkk23wkIrQNu53knz7A0WbxbyYv92p0ajjZYMz81T9avt+Kh9prgzxFkzHYZULrvdui08SDQYloxo+yRzRghWZfxSCWSTpPV9NU6ldMNepZ7HwY84uD8ow5Ihbh7A+CbLPCYkVl6Z3sU3epCaYQIPgg6KFyeaZ2Be5GP/Lx6wPTFZugoL5FBOeJwFepOCcn7qVsyL1SrYm5XyNr2oimHnVTZBVFNY+cawXvD27dzJ2ML3w99fzpktnuaY1gnuxy+9l24wCFVE7CHkQwz8mkF8VixE3MRn1K/zvk/aWJ2twRp4Tws9OTKZq0g2xs3YSitVHk5DQDG8= johannes@pop-os"
    ];
  };

  # Sudo privileges
  security.sudo.wheelNeedsPassword = false;

  # OpenSSH daemon baseline
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Networking and Firewall baseline
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };

  # Universal system tooling
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    rsync
    pciutils
    usbutils
  ];
}
