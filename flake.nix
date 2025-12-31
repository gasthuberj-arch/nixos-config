{
  description = "NixOS server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, impermanence, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

    in
    {
      # NixOS configurations
      nixosConfigurations = {
        # Homelab server with two-tier ZFS storage
        homelab = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs pkgs-unstable;
          };
          modules = [
            # Disk configuration
            disko.nixosModules.disko

            # Secrets management
            sops-nix.nixosModules.sops

            # Host-specific configuration
            ./hosts/homelab/configuration.nix
          ];
        };

        # Installation ISO with homelab config
        homelab-installer = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs pkgs-unstable;
          };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

            # Include disko on the ISO
            disko.nixosModules.disko

            {
              # Pre-configure the installer with your settings
              environment.systemPackages = with pkgs; [
                git
                vim
                tmux
                htop
              ];

              # Enable flakes
              nix.settings.experimental-features = [ "nix-command" "flakes" ];

              # Pre-load your config
              environment.etc."nixos-config".source = self;
            }
          ];
        };
      };

      # ISO image output
      packages.x86_64-linux.iso = self.nixosConfigurations.homelab-installer.config.system.build.isoImage;
    };
}
