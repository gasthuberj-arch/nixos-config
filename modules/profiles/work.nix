{
  config,
  pkgs,
  ...
}: let
  # intune-agent's compliance check parses this line directly out of
  # whichever of these three distro-conventional PAM files exists.
  pwqualityCheckLine = "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so retry=3 minlen=8 enforce_for_root";
in {
  # IPv6 here is local-only (ULA, no default route) but DNS still returns
  # public AAAA records, so apps without Happy-Eyeballs fallback (e.g.
  # intune-portal's HTTP client) fail outright instead of trying IPv4.
  networking.enableIPv6 = false;
  networking.networkmanager.dns = "dnsmasq"; # NM runs its own local dnsmasq resolver

  environment.etc."NetworkManager/dnsmasq.d/qualitatio-wildcard.conf".text = ''
    address=/qualitatio.test/192.168.122.141
  '';

  # The native 3.0.1 microsoft-identity-broker (current nixpkgs default)
  # can't complete interactive sign-in here; pin back to the last
  # Java-based release. See pkgs/microsoft-identity-broker-2.0.1.nix.
  nixpkgs.overlays = [
    (final: prev: {
      microsoft-identity-broker = final.callPackage ../../pkgs/microsoft-identity-broker-2.0.1.nix {};
    })
  ];

  services.intune.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Intune compliance policy requires a minimum password length (8). The
  # intune-agent binary (verified via `strings`) checks this by directly
  # parsing a pam_pwquality "minlen=" argument out of one of three
  # distro-conventional PAM include files: /etc/pam.d/common-password
  # (Debian/Ubuntu), /etc/pam.d/system-password, or /etc/pam.d/password-auth
  # (RHEL/Fedora). None of these exist on NixOS (services have their own
  # independent PAM stacks, no shared include), so the compliance check
  # sees actual_value=0 regardless of what's actually enforced. These
  # files aren't included by any real PAM stack here — they only need to
  # exist with the right content for the checker to find.
  environment.etc."pam.d/common-password".text = pwqualityCheckLine;
  environment.etc."pam.d/system-password".text = pwqualityCheckLine;
  environment.etc."pam.d/password-auth".text = pwqualityCheckLine;

  security.pam.services.passwd.rules.password.pwquality = {
    control = "requisite";
    modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
    order = config.security.pam.services.passwd.rules.password.unix.order - 10;
    settings = {
      retry = 3;
      minlen = 8;
      enforce_for_root = true;
    };
  };
}
