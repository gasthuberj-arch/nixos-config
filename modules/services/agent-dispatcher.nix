# Agent orbs + batch issue dispatcher (host control plane, ADR-0005/0006).
#
# The interesting logic lives in plain files next to this module:
#   agent-dispatcher/isolation.nft             egress firewall for the VM bridge
#   agent-dispatcher/mint-github-app-token.sh  1-hour single-repo GitHub tokens
#   agent-dispatcher/orb.sh                    `orb`: spawn/pause/delete/attach
#   agent-dispatcher/agent-dispatch-once.sh    one issue -> batch orb -> PR
#   agent-dispatcher/agent-dispatch-poll.sh    timer: find labelled issues
#
# With only `enable = true` you get the isolated network and `sudo orb`
# (no GitHub secrets needed; orbs then have no GitHub token). Set the GitHub
# App options to give orbs tokens, plus `repositories` for issue polling.
#
# Manual state under /persist/orbs (root, 0700):
#   ssh/id_ed25519   generated on first use; its .pub goes to every orb
#   agy-cred/        contents of a logged-in agy ~/.gemini, copied into
#                    orbs of `orbs.agyRepos` only
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.homelab.services.agentDispatcher;
  orbCfg = config.homelab.services.orbs;

  runDir = "/run/agent-dispatcher";
  orbStateRoot = "/persist/orbs";
  vmUser = "agent-vm";
  zfsParent = "rpool/orbs";
  zfsQuota = "20G";
  bridge = "br-agent";
  githubApp = cfg.githubAppId != null && cfg.githubAppInstallationId != null && cfg.githubPrivateKeyFile != null;

  # One evaluated guest per slot: microvm.nix bakes TAP, MAC, CID and share
  # paths into the runner at eval time, so slots are separate systems.
  slots = lib.range 1 orbCfg.maxConcurrent;
  mkSlot = n: let
    vm = inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      specialArgs = {inherit inputs;};
      modules = [
        inputs.microvm.nixosModules.microvm
        ../microvms/agent-worker.nix
        {
          agentWorker = {
            slot = n;
            inherit (cfg.worker) vcpu memMb agentBackend agentPackages customAgentCommand;
          };
        }
      ];
    };
  in {
    inherit vm;
    inherit (vm.config.agentWorker) derived;
    launcher = pkgs.callPackage ../../pkgs/agent-vm-launcher.nix {
      name = "orb-slot${toString n}-vm";
      inherit vm;
    };
  };
  slotVms = lib.genAttrs (map toString slots) (n: mkSlot (lib.toInt n));
  taps = map (s: s.derived.tapId) (lib.attrValues slotVms);
  # virtiofsd runs as agent-vm, so the guest sees every shared file as owned
  # by agent-vm's ids; they are taken from the guest's `user`.
  guestUsers = slotVms."1".vm.config.users;
  vmUid = guestUsers.users.user.uid;
  vmGid = guestUsers.groups.user.gid;

  # Everything orb.sh knows about a slot comes from the evaluated guest.
  slotsJson = pkgs.writeText "orb-slots.json" (builtins.toJSON (lib.mapAttrs (_: s: {
      launcher = lib.getExe s.launcher;
      inherit (s.derived) slotDir jobDir workspaceDir stateDir vsockSocket;
    })
    slotVms));
  orbRunDir = dirOf slotVms."1".derived.slotDir;

  networkScript =
    ''
      ip link show ${bridge} >/dev/null 2>&1 || ip link add ${bridge} type bridge
      ip addr replace 10.240.0.1/24 dev ${bridge}
      ip link set ${bridge} up
    ''
    + lib.concatMapStrings (s: let
      inherit (s.derived) tapId;
    in ''
      ip link show ${tapId} >/dev/null 2>&1 || \
        ip tuntap add name ${tapId} mode tap user ${vmUser} \
          ${lib.optionalString s.vm.config.microvm.declaredRunner.passthru.tapMultiQueue "multi_queue"}
      ip link set ${tapId} master ${bridge} up
    '') (lib.attrValues slotVms)
    + ''
      nft -f ${./agent-dispatcher/isolation.nft}
    '';

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

  orb = pkgs.writeShellApplication {
    name = "orb";
    runtimeInputs =
      lib.optional githubApp mintToken
      ++ [config.boot.zfs.package]
      ++ (with pkgs; [jq coreutils findutils gnused util-linux systemd nftables openssh]);
    runtimeEnv = {
      ORB_SLOTS_JSON = slotsJson;
      ORB_RUN_DIR = orbRunDir;
      ORB_STATE_ROOT = orbStateRoot;
      ZFS_PARENT = zfsParent;
      ZFS_QUOTA = zfsQuota;
      VM_USER = vmUser;
      VM_UID = toString vmUid;
      VM_GID = toString vmGid;
      TIMEOUT_SECONDS = toString cfg.worker.timeoutSeconds;
      SSH_PROXY = "${config.systemd.package}/lib/systemd/systemd-ssh-proxy";
      MEMORY_MAX = "${toString (cfg.worker.memMb + 512)}M";
      CPU_QUOTA = "${toString (cfg.worker.vcpu * 100)}%";
      GITHUB_APP =
        if githubApp
        then "1"
        else "0";
      AGY_REPOS = lib.concatStringsSep " " orbCfg.agyRepos;
      LLM_API_KEY_FILE = toString cfg.llmApiKeyFile;
      LLM_API_KEY_ENV = cfg.llmApiKeyEnvVar;
    };
    # jq programs are single-quoted on purpose; their $vars are jq's.
    excludeShellChecks = ["SC2016"];
    text = builtins.readFile ./agent-dispatcher/orb.sh;
  };

  dispatchOnce = pkgs.writeShellApplication {
    name = "agent-dispatch-once";
    runtimeInputs = [mintToken orb] ++ (with pkgs; [gh jq coreutils]);
    runtimeEnv = {
      RUN_DIR = runDir;
      TRIGGER_LABEL = cfg.triggerLabel;
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
        description = "Wall-clock limit for batch orbs. Interactive orbs have none.";
      };
      agentBackend = lib.mkOption {
        type = lib.types.enum ["antigravity" "claude-code" "opencode" "aider" "custom"];
        default = "antigravity";
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

  # Orbs are the VM layer under the dispatcher; enabled with it.
  options.homelab.services.orbs = {
    maxConcurrent = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 4;
      description = "Slots = orbs running at once (interactive and batch share them).";
    };
    agyRepos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = cfg.repositories;
      defaultText = lib.literalExpression "config.homelab.services.agentDispatcher.repositories";
      description = "OWNER/REPO whose orbs get a copy of the agy credential (a Google refresh token).";
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
      uid = vmUid;
      group = vmUser;
    };
    users.groups.${vmUser}.gid = vmGid;

    environment.systemPackages = [orb dispatchOnce mintToken pkgs.nftables];

    systemd.tmpfiles.rules = [
      "d ${orbStateRoot} 0700 root root -"
      "d ${orbStateRoot}/agy-cred 0700 root root -"
    ];

    # --- Isolated network: bridge + one TAP per slot + firewall table -----
    boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkDefault true;
    networking.networkmanager.unmanaged = [bridge] ++ taps;

    systemd.services.agent-dispatcher-network = {
      description = "Isolated bridge, TAP and egress firewall for agent microVMs";
      wantedBy = ["multi-user.target"];
      after = ["network-pre.target"];
      path = with pkgs; [iproute2 nftables];
      # A restart on `switch` would run preStop and delete the TAPs under
      # running orbs. The script is idempotent, so a reload re-applies it.
      reloadIfChanged = true;
      reload = networkScript;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = networkScript;
      preStop = ''
        nft delete table inet agent-isolation || true
        ${lib.concatMapStrings (t: "ip link del ${t} || true\n") taps}
        ip link del ${bridge} || true
      '';
    };

    # --- Orbs: parent dataset, ssh key, reboot recovery -------------------
    # After a reboot /run is empty, so every "running" entry is stale: it is
    # marked paused (orbs never auto-start, ADR-0006).
    systemd.services.orbs-init = {
      description = "Prepare agent orb storage and mark orbs from before the boot paused";
      wantedBy = ["multi-user.target"];
      after = ["zfs-import.target" "local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe orb} _boot";
      };
    };

    # Expire idle orbs, purge trash, reap orphans (ADR-0006). Named orbs-*
    # because orb-<id> is the namespace of the orbs' own units.
    systemd.services.orbs-gc = {
      description = "Garbage-collect agent orbs";
      requires = ["orbs-init.service"];
      after = ["orbs-init.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe orb} gc";
      };
    };
    systemd.timers.orbs-gc = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # Tokens live 1 hour; re-mint every 30 min into each running orb.
    systemd.services.orbs-token-refresh = lib.mkIf githubApp {
      description = "Re-mint GitHub tokens of running agent orbs";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe orb} refresh-tokens";
      };
    };
    systemd.timers.orbs-token-refresh = lib.mkIf githubApp {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30min";
        OnUnitActiveSec = "30min";
      };
    };

    # --- Polling (only once repositories are configured) -----------------
    systemd.services.agent-dispatcher = {
      description = "Run agent microVM jobs for labelled GitHub issues";
      requires = ["agent-dispatcher-network.service" "orbs-init.service"];
      after = ["agent-dispatcher-network.service" "orbs-init.service" "network-online.target"];
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
