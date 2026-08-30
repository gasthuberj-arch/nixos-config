{
  description = "NixOS server configuration";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

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

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nixos-raspberrypi,
    disko,
    sops-nix,
    git-hooks,
    jetpack-nixos,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    rpiSystem = "aarch64-linux";

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
  in {
    # Pre-commit & CI quality checks
    checks.${system} = {
      pre-commit-check = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          alejandra.enable = true;
          deadnix.enable = true;
          statix.enable = true;
          gitleaks = {
            enable = true;
            name = "gitleaks";
            entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --verbose";
            pass_filenames = false;
          };
        };
      };
    };

    # Development shell with automated git hooks
    devShells.${system}.default = pkgs.mkShell {
      inherit (self.checks.${system}.pre-commit-check) shellHook;
      buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
    };

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
            boot.zfs.forceImportRoot = false;

            # Pre-configure the installer with your settings
            environment.systemPackages = with pkgs; [
              git
              vim
              tmux
              htop
            ];

            # Enable flakes
            nix.settings.experimental-features = ["nix-command" "flakes"];

            # Pre-load your config
            environment.etc."nixos-config".source = self;
          }
        ];
      };

      rpi5 = nixos-raspberrypi.lib.nixosSystem {
        system = rpiSystem;
        specialArgs = inputs // {inherit nixos-raspberrypi;};
        modules = [
          ./hosts/rpi5/configuration.nix
        ];
      };

      laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs pkgs-unstable self;
        };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/laptop/configuration.nix
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit self inputs pkgs-unstable;
            };
            home-manager.users.johannes = import ./hosts/laptop/home.nix;
          }
        ];
      };

      orin-nx = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs pkgs-unstable;
        };
        modules = [
          jetpack-nixos.nixosModules.default
          ./hosts/orin-nx/configuration.nix
        ];
      };
    };
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    # Package outputs
    packages.x86_64-linux = {
      iso = self.nixosConfigurations.homelab-installer.config.system.build.isoImage;
      rpi5-sd-image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
      orin-nx-flash = self.nixosConfigurations.orin-nx.config.system.build.flashScript;
      antigravity = pkgs.callPackage ./pkgs/antigravity.nix {};
      agy = self.packages.x86_64-linux.antigravity;
    };
  };
}
