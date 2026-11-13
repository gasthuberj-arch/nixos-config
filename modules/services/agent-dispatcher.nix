# Ephemeral microVM agent dispatcher (host control plane).
#
# The interesting logic lives in plain files next to this module:
#   agent-dispatcher/isolation.nft             egress firewall for the VM bridge
#   agent-dispatcher/mint-github-app-token.sh  1-hour single-repo GitHub tokens
#   agent-dispatcher/agent-dispatch-once.sh    one issue -> one VM -> one PR
#   agent-dispatcher/agent-dispatch-poll.sh    timer: find labelled issues
#
# With only `enable = true` you get the isolated network and `agent-vm-shell`
# (no GitHub secrets needed). Set `repositories` + the GitHub App options to
# turn on automatic issue polling.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.homelab.services.agentDispatcher;

  runDir = "/run/agent-dispatcher";
  vmUser = "agent-vm";
  bridge = "br-agent";
  tap = "tap-agent0";

  workerVm = inputs.nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    specialArgs = {inherit inputs;};
    modules = [
      inputs.microvm.nixosModules.microvm
      ../microvms/agent-worker.nix
      {
        networking.hostName = lib.mkForce "agent-worker";
        agentWorker = {
          jobDir = "${runDir}/current-job";
          network = {
            enable = true;
            tapId = tap;
          };
          inherit (cfg.worker) vcpu memMb agentBackend agentPackages customAgentCommand;
        };
      }
    ];
  };

  launcher = pkgs.callPackage ../../pkgs/agent-vm-launcher.nix {
    name = "agent-worker-vm";
    vm = workerVm;
  };

  mintToken = pkgs.writeShellApplication {
    name = "mint-github-app-token";
    runtimeInputs = with pkgs; [openssl curl jq coreutils];
    runtimeEnv = {
      GITHUB_APP_ID = toString cfg.githubAppId;
      GITHUB_APP_INSTALLATION_ID = toString cfg.githubAppInstallationId;
      GITHUB_APP_KEY_FILE = toString cfg.githubPrivateKeyFile;
    };
    text = builtins.readFile ./agent-dispatcher/mint-github-app-token.sh;
  };

  dispatchOnce = pkgs.writeShellApplication {
    name = "agent-dispatch-once";
    runtimeInputs = [mintToken] ++ (with pkgs; [gh jq coreutils util-linux systemd nftables]);
    runtimeEnv = {
      RUN_DIR = runDir;
      VM_USER = vmUser;
      LAUNCHER = lib.getExe launcher;
      TIMEOUT_SECONDS = toString cfg.worker.timeoutSeconds;
      MEMORY_MAX = "${toString (cfg.worker.memMb + 512)}M";
      CPU_QUOTA = "${toString (cfg.worker.vcpu * 100)}%";
      TRIGGER_LABEL = cfg.triggerLabel;
      LLM_API_KEY_FILE = toString cfg.llmApiKeyFile;
      LLM_API_KEY_ENV = cfg.llmApiKeyEnvVar;
    };
    text = builtins.readFile ./agent-dispatcher/agent-dispatch-once.sh;
  };

  dispatchPoll = pkgs.writeShellApplication {
    name = "agent-dispatch-poll";
    runtimeInputs = [mintToken dispatchOnce pkgs.gh];
    runtimeEnv = {
      REPOSITORIES = lib.concatStringsSep " " cfg.repositories;
      TRIGGER_LABEL = cfg.triggerLabel;
    };
    text = builtins.readFile ./agent-dispatcher/agent-dispatch-poll.sh;
  };

  vmShell = pkgs.writeShellScriptBin "agent-vm-shell" ''
    exec ${lib.getExe dispatchOnce} --shell "$@"
  '';

  # Secrets are runtime paths (sops-nix), never Nix paths: a Nix path literal
  # would copy the secret into the world-readable /nix/store.
  secretPath = lib.types.nullOr (lib.types.strMatching "/.*");
in {
  options.homelab.services.agentDispatcher = {
    enable = lib.mkEnableOption "ephemeral microVM GitHub issue agent dispatcher";

    pollInterval = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "How often to poll `repositories` for issues labelled `triggerLabel`.";
    };
    triggerLabel = lib.mkOption {
      type = lib.types.str;
      default = "agent-ready";
    };
    repositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["gasthuberj-arch/nixos-config"];
      description = "OWNER/REPO list to poll. Empty disables the timer.";
    };

    githubAppId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    githubAppInstallationId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    githubPrivateKeyFile = lib.mkOption {
      type = secretPath;
      default = null;
      description = "Runtime path of the GitHub App PEM key (e.g. a sops-nix secret).";
    };
    llmApiKeyFile = lib.mkOption {
      type = secretPath;
      default = null;
      description = "Runtime path of the API key for the agent CLI.";
    };
    llmApiKeyEnvVar = lib.mkOption {
      type = lib.types.str;
      default = "ANTHROPIC_API_KEY";
    };

    worker = {
      vcpu = lib.mkOption {
        type = lib.types.int;
        default = 4;
      };
      memMb = lib.mkOption {
        type = lib.types.int;
        default = 4096;
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.int;
        default = 1800;
      };
      agentBackend = lib.mkOption {
        type = lib.types.enum ["claude-code" "opencode" "aider" "custom"];
        default = "claude-code";
      };
      agentPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        example = lib.literalExpression "[ pkgs.claude-code ]";
      };
      customAgentCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.repositories
          == []
          || (cfg.githubAppId != null && cfg.githubAppInstallationId != null && cfg.githubPrivateKeyFile != null);
        message = "homelab.services.agentDispatcher: repositories needs githubAppId, githubAppInstallationId and githubPrivateKeyFile";
      }
    ];

    users.users.${vmUser} = {
      isSystemUser = true;
      group = vmUser;
    };
    users.groups.${vmUser} = {};

    environment.systemPackages = [dispatchOnce vmShell mintToken pkgs.nftables];

    # --- Isolated network: bridge + TAP + firewall table ------------------
    boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkDefault true;
    networking.networkmanager.unmanaged = [bridge tap];

    systemd.services.agent-dispatcher-network = {
      description = "Isolated bridge, TAP and egress firewall for agent microVMs";
      wantedBy = ["multi-user.target"];
      after = ["network-pre.target"];
      path = with pkgs; [iproute2 nftables];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ip link show ${bridge} >/dev/null 2>&1 || ip link add ${bridge} type bridge
        ip addr replace 10.240.0.1/24 dev ${bridge}
        ip link set ${bridge} up
        ip link show ${tap} >/dev/null 2>&1 || \
          ip tuntap add name ${tap} mode tap user ${vmUser} \
            ${lib.optionalString workerVm.config.microvm.declaredRunner.passthru.tapMultiQueue "multi_queue"}
        ip link set ${tap} master ${bridge} up
        nft -f ${./agent-dispatcher/isolation.nft}
      '';
      preStop = ''
        nft delete table inet agent-isolation || true
        ip link del ${tap} || true
        ip link del ${bridge} || true
      '';
    };

    # --- Polling (only once repositories are configured) -----------------
    systemd.services.agent-dispatcher = {
      description = "Run agent microVM jobs for labelled GitHub issues";
      requires = ["agent-dispatcher-network.service"];
      after = ["agent-dispatcher-network.service" "network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe dispatchPoll;
      };
    };

    systemd.timers.agent-dispatcher = lib.mkIf (cfg.repositories != []) {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitInactiveSec = cfg.pollInterval;
      };
    };
  };
}
