# Ephemeral agent microVM guest.
#
# One guest definition, two modes:
#   - interactive sandbox (`nix run .#agent-vm-sandbox`): no job share,
#     serial console autologin, nothing runs automatically.
#   - automated worker (homelab agentDispatcher): the host sets `jobDir`,
#     `agent-job-runner` processes /run/agent-job and the VM powers off.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.agentWorker;

  runner = pkgs.writeShellApplication {
    name = "agent-job-runner";
    runtimeInputs =
      (with pkgs; [git gh jq coreutils nix bash])
      ++ cfg.agentPackages;
    text = builtins.readFile ./agent-job-runner.sh;
  };

  # Builds a tiny derivation entirely offline so you can watch the result
  # land in the tmpfs upper layer of the /nix/store overlay.
  overlayDemo = pkgs.writeShellScriptBin "overlay-demo" ''
    set -euo pipefail
    out=$(nix build --no-link --print-out-paths --impure --expr '
      derivation {
        name = "overlay-demo-'"$(date +%s)"'";
        system = builtins.currentSystem;
        builder = "''${builtins.storePath "${pkgs.bash}"}/bin/bash";
        args = [ "-c" "echo built inside the microVM > $out" ];
      }')
    echo "built: $out"
    echo "lower (host, read-only): $(ls /nix/.ro-store/$(basename "$out") 2>&1 || true)"
    echo "upper (guest tmpfs):     $(ls -d ${config.microvm.writableStoreOverlay}/store/$(basename "$out"))"
  '';
in {
  options.agentWorker = {
    jobDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host directory shared into the guest at /run/agent-job. null = interactive sandbox.";
    };
    vcpu = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };
    memMb = lib.mkOption {
      type = lib.types.int;
      default = 2048;
    };
    agentBackend = lib.mkOption {
      type = lib.types.enum ["claude-code" "opencode" "aider" "custom"];
      default = "claude-code";
    };
    agentPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Packages providing the agent CLI (and anything else it needs).";
    };
    customAgentCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Command run in the repo when agentBackend = \"custom\". Receives $SPEC_FILE.";
    };
    network = {
      enable = lib.mkEnableOption "TAP networking (host must provide the tap device)";
      tapId = lib.mkOption {
        type = lib.types.str;
        default = "tap-agent0";
      };
      address = lib.mkOption {
        type = lib.types.str;
        default = "10.240.0.2/24";
      };
      gateway = lib.mkOption {
        type = lib.types.str;
        default = "10.240.0.1";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.agentBackend != "custom" || cfg.customAgentCommand != null;
        message = "agentWorker.customAgentCommand must be set when agentBackend = \"custom\"";
      }
    ];

    networking.hostName = "agent-sandbox";
    system.stateVersion = "26.05";

    # --- Hypervisor & store ---------------------------------------------
    microvm = {
      hypervisor = "cloud-hypervisor";
      inherit (cfg) vcpu;
      mem = cfg.memMb;
      vsock.cid = 3;

      shares =
        [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
          }
        ]
        ++ lib.optional (cfg.jobDir != null) {
          tag = "agent-job";
          source = cfg.jobDir;
          mountPoint = "/run/agent-job";
          proto = "virtiofs";
        };

      # tmpfs upper layer over the read-only host store: builds stay in RAM.
      writableStoreOverlay = "/nix/.rw-store";

      interfaces = lib.optional cfg.network.enable {
        type = "tap";
        id = cfg.network.tapId;
        mac = "02:00:00:a6:e0:02";
      };
    };

    # --- Ephemeral filesystems (root is tmpfs by microvm.nix default) -----
    fileSystems = {
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=50%" "mode=1777"];
      };
      "/var/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=50%" "mode=1777"];
      };
    };

    # --- Networking (only when the host provides a TAP) -------------------
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.firewall.enable = false; # the host firewall is the boundary
    systemd.network.networks."10-agent" = lib.mkIf cfg.network.enable {
      matchConfig.Type = "ether";
      address = [cfg.network.address];
      gateway = [cfg.network.gateway];
      # Public resolvers only: never ask the homelab split-horizon DNS.
      dns = ["1.1.1.1" "9.9.9.9"];
    };

    # --- Nix inside the guest ---------------------------------------------
    nix = {
      settings.experimental-features = ["nix-command" "flakes"];
      channel.enable = false;
      registry.nixpkgs.flake = inputs.nixpkgs;
      nixPath = ["nixpkgs=${inputs.nixpkgs}"];
    };

    environment.systemPackages =
      (with pkgs; [
        # base
        git
        gh
        curl
        jq
        ripgrep
        fd
        gnugrep
        gnused
        gawk
        coreutils
        bash
        cacert
        procps
        iproute2
        iputils
        # nix quality suite (matches flake pre-commit hooks)
        alejandra
        statix
        deadnix
        gitleaks
        # build baselines
        python3
        nodejs
        gcc
        gnumake
        pkg-config
      ])
      ++ [runner overlayDemo]
      ++ cfg.agentPackages;

    # --- Interactive mode: root shell on the serial console ---------------
    services.getty.autologinUser = "root";
    users.users.root.initialHashedPassword = "";

    # --- Automated mode: one job, then power off --------------------------
    systemd.services.agent-job-runner = {
      description = "Turn the GitHub issue in /run/agent-job into a pull request";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "run-agent\\x2djob.mount"];
      wants = ["network-online.target"];
      unitConfig = {
        ConditionPathExists = "/run/agent-job/job.json";
        SuccessAction = "poweroff";
        FailureAction = "poweroff";
      };
      environment = {
        AGENT_BACKEND = cfg.agentBackend;
        CUSTOM_AGENT_COMMAND = lib.optionalString (cfg.customAgentCommand != null) cfg.customAgentCommand;
        HOME = "/root";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe runner;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };
  };
}
