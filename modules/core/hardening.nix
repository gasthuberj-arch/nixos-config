{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.hardening;

  # Reusable systemd service confinement preset. Uses lib.mkDefault on baseline
  # hardening directives so upstream NixOS service modules can override or extend
  # individual settings without conflicting definitions.
  mkHardenedService = {
    allowJit ? false,
    allowGpu ? false,
    readWritePaths ? [],
    inaccessiblePaths ? [],
    extraConfig ? {},
  }:
    (lib.optionalAttrs cfg.enable (
      {
        ProtectSystem = lib.mkDefault "strict";
        ProtectHome = lib.mkDefault true;
        PrivateTmp = lib.mkDefault true;
        NoNewPrivileges = lib.mkDefault true;
        PrivateDevices = lib.mkDefault (!allowGpu);
        DevicePolicy = lib.mkDefault (
          if allowGpu
          then "auto"
          else "closed"
        );
        ProtectKernelTunables = lib.mkDefault true;
        ProtectKernelModules = lib.mkDefault true;
        ProtectKernelLogs = lib.mkDefault true;
        ProtectControlGroups = lib.mkDefault true;
        ProtectClock = lib.mkDefault true;
        ProtectHostname = lib.mkDefault true;
        RestrictSUIDSGID = lib.mkDefault true;
        RestrictRealtime = lib.mkDefault true;
        RestrictNamespaces = lib.mkDefault true;
        LockPersonality = lib.mkDefault true;
        MemoryDenyWriteExecute = lib.mkDefault (!allowJit);
        SystemCallArchitectures = lib.mkDefault "native";
      }
      // lib.optionalAttrs (readWritePaths != []) {
        ReadWritePaths = readWritePaths;
      }
      // lib.optionalAttrs (inaccessiblePaths != []) {
        InaccessiblePaths = inaccessiblePaths;
      }
    ))
    // extraConfig;

  # Shared option generator for per-service systemd hardening toggles.
  mkHardeningOptions = {
    service,
    defaultAllowJit ? false,
    allowGpuOption ? false,
    defaultAllowGpu ? false,
  }:
    {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable systemd confinement for ${service}";
      };

      allowJit = lib.mkOption {
        type = lib.types.bool;
        default = defaultAllowJit;
        description = "Allow writable/executable memory mappings (JIT) for ${service}";
      };
    }
    // lib.optionalAttrs allowGpuOption {
      allowGpu = lib.mkOption {
        type = lib.types.bool;
        default = defaultAllowGpu;
        description = "Allow GPU hardware acceleration device access for ${service}";
      };
    };
in {
  options.homelab = {
    persistence = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Per-service /var/lib state directories registered for root impermanence.";
      };
    };

    hardening = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable reusable systemd confinement and runtime secret assertions.";
      };

      secretPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Registered runtime secret file paths verified not to reside in the Nix store.";
      };
    };
  };

  config = {
    _module.args = {
      inherit mkHardenedService mkHardeningOptions;
    };

    assertions = [
      {
        assertion = lib.all (p: !(lib.hasPrefix builtins.storeDir p)) cfg.secretPaths;
        message = "Runtime secret paths must not reside inside ${builtins.storeDir}; use /run/secrets/* or persisted secret files.";
      }
    ];
  };
}
