# Agent microVM guest ("orb").
#
# One guest definition, two modes:
#   - interactive sandbox (`nix run .#agent-vm-sandbox`, slot = null): only
#     the store is shared, no network, serial console autologin.
#   - orb in slot N (homelab orbs): job + workspace shares, TAP networking,
#     sshd on vsock. If the host put spec.md into the job share,
#     `agent-job-runner` handles it and the VM powers off; otherwise the VM
#     stays up for interactive work until `poweroff`.
#
# Everything that differs between slots is derived from `slot` here and
# exposed as `agentWorker.derived`; the host reads it from the evaluated VM
# config and never re-derives it.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.agentWorker;
  orb = cfg.slot != null;
  d = cfg.derived;

  jobMount = "/run/orb-job";
  home = "/home/user";
  # The host gives agent-vm (virtiofsd) these ids, read from users.users.user
  # here, so files on the shares are owned by `user` inside the guest.
  uid = 2000;

  antigravity = pkgs.callPackage ../../pkgs/antigravity.nix {};

  runner = pkgs.writeShellApplication {
    name = "agent-job-runner";
    runtimeInputs =
      (with pkgs; [git jq coreutils nix bash])
      ++ [ghFresh]
      ++ cfg.agentPackages;
    text = builtins.readFile ./agent-job-runner.sh;
  };

  # The host rewrites github_token while the orb runs, so both helpers read
  # it on every call instead of caching it in the environment.
  gitCredentialOrb = pkgs.writeShellScript "git-credential-orb" ''
    [ "$1" = get ] || exit 0
    [ -r ${jobMount}/github_token ] || exit 0
    echo username=x-access-token
    echo "password=$(cat ${jobMount}/github_token)"
  '';
  ghFresh = pkgs.writeShellScriptBin "gh" ''
    if [ -r ${jobMount}/github_token ]; then
      GH_TOKEN=$(cat ${jobMount}/github_token)
      export GH_TOKEN
    fi
    exec ${lib.getExe pkgs.gh} "$@"
  '';

  orbClone = pkgs.writeShellApplication {
    name = "orb-clone";
    runtimeInputs = with pkgs; [git jq coreutils];
    text = ''
      repo=$(jq -r .repo ${jobMount}/orb.json)
      branch=$(jq -r '.branch // empty' ${jobMount}/orb.json)
      dir=${home}/$(basename "$repo")
      [ -e "$dir" ] && exit 0
      # Leftover of a failed clone on the persistent dataset.
      rm -rf "$dir.partial"
      url="https://github.com/$repo.git"
      # A branch that does not exist upstream yet is created from the default branch.
      if [ -n "$branch" ] && git ls-remote --exit-code --heads "$url" "$branch" >/dev/null; then
        git clone --branch "$branch" "$url" "$dir.partial"
      else
        git clone "$url" "$dir.partial"
        if [ -n "$branch" ]; then git -C "$dir.partial" switch -c "$branch"; fi
      fi
      mv "$dir.partial" "$dir"
    '';
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
    slot = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 1 99);
      default = null;
      description = "Orb slot N. null = interactive sandbox (store share only, no network).";
    };
    derived = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Per-slot values derived from `slot`, read by the host: tapId, mac, ip, address, gateway, cid, hostName, and the host-side share paths.";
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
      type = lib.types.enum ["antigravity" "claude-code" "opencode" "aider" "custom"];
      default = "antigravity";
    };
    agentPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Packages providing the agent CLI (and anything else it needs). agy is always installed.";
    };
    customAgentCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Command run in the repo when agentBackend = \"custom\". Receives $SPEC_FILE.";
    };
    network.enable = lib.mkOption {
      type = lib.types.bool;
      default = orb;
      defaultText = lib.literalExpression "config.agentWorker.slot != null";
      description = "TAP networking (the host must provide derived.tapId on br-agent).";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.agentBackend != "custom" || cfg.customAgentCommand != null;
        message = "agentWorker.customAgentCommand must be set when agentBackend = \"custom\"";
      }
      {
        assertion = !cfg.network.enable || orb;
        message = "agentWorker.network.enable requires agentWorker.slot";
      }
    ];

    agentWorker.derived = let
      n = cfg.slot;
      slotDir = "/run/orbs/slot${toString n}";
      hex = lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString n));
    in
      if orb
      then {
        slot = n;
        tapId = "tap-orb${toString n}";
        mac = "02:00:00:a6:e0:${hex}";
        ip = "10.240.0.${toString (10 + n)}";
        address = "10.240.0.${toString (10 + n)}/24";
        gateway = "10.240.0.1";
        cid = 10 + n;
        hostName = "orb${toString n}";
        inherit slotDir;
        jobDir = "${slotDir}/job";
        workspaceDir = "${slotDir}/workspace";
        stateDir = "${slotDir}/vm";
        # cloud-hypervisor hybrid vsock: microvm.nix names it relative to the
        # runner's cwd, which the launcher sets to AGENT_VM_STATE_DIR.
        vsockSocket = "${slotDir}/vm/notify.vsock";
      }
      else {
        slot = null;
        cid = 3;
        hostName = "agent-sandbox";
      };

    networking.hostName = d.hostName;
    system.stateVersion = "26.05";

    # --- Hypervisor & store ---------------------------------------------
    microvm = {
      hypervisor = "cloud-hypervisor";
      inherit (cfg) vcpu;
      mem = cfg.memMb;
      vsock.cid = d.cid;

      shares =
        [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
          }
        ]
        ++ lib.optionals orb [
          {
            tag = "orb-job";
            source = d.jobDir;
            mountPoint = jobMount;
            proto = "virtiofs";
          }
          {
            tag = "orb-home";
            source = d.workspaceDir;
            mountPoint = home;
            proto = "virtiofs";
          }
        ];

      # tmpfs upper layer over the read-only host store: builds stay in RAM.
      writableStoreOverlay = "/nix/.rw-store";

      interfaces = lib.optional cfg.network.enable {
        type = "tap";
        id = d.tapId;
        inherit (d) mac;
      };
    };

    # --- Filesystems (root is tmpfs by microvm.nix default) ---------------
    fileSystems =
      {
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
      }
      // lib.optionalAttrs orb {
        # agy's Google refresh token must never land on the orb dataset or
        # its snapshots, so ~/.gemini is RAM only.
        "${home}/.gemini" = {
          device = "tmpfs";
          fsType = "tmpfs";
          options = ["size=64m" "mode=0700" "uid=${toString uid}" "gid=${toString uid}"];
        };
      };

    # --- Networking (only when the host provides a TAP) -------------------
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.firewall.enable = false; # the host firewall is the boundary
    systemd.network.networks."10-agent" = lib.mkIf cfg.network.enable {
      matchConfig.Type = "ether";
      address = [d.address];
      gateway = [d.gateway];
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

    programs.git = {
      enable = true;
      config = {
        credential."https://github.com".helper = "${gitCredentialOrb}";
        user = {
          name = "agent-worker[bot]";
          email = "agent-worker[bot]@users.noreply.github.com";
        };
      };
    };

    environment.systemPackages =
      (with pkgs; [
        # base
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
        tmux
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
      ++ [ghFresh antigravity runner overlayDemo]
      ++ cfg.agentPackages;

    # --- Users ------------------------------------------------------------
    users.groups.user.gid = uid;
    users.users.user = {
      isNormalUser = true;
      inherit uid home;
      group = "user";
      extraGroups = ["wheel"];
    };
    security.sudo.wheelNeedsPassword = false;

    # Serial console: root shell (sandbox), or debugging via the host journal.
    services.getty.autologinUser = "root";
    users.users.root.initialHashedPassword = "";

    # --- sshd on AF_VSOCK only (orbs) -------------------------------------
    services.openssh = lib.mkIf orb {
      enable = true;
      startWhenNeeded = true;
      openFirewall = false;
      authorizedKeysFiles = ["${jobMount}/authorized_keys"];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = ["user"];
      };
    };
    # Replaces the TCP listener; the host reaches it through the CH vsock socket.
    # Must be socketConfig.ListenStream: `listenStreams` only appends, leaving [::]:22.
    systemd.sockets.sshd = lib.mkIf orb {
      socketConfig.ListenStream = lib.mkForce ["vsock::22"];
    };
    # systemd-ssh-generator would bind its own sshd-vsock.socket to vsock:22
    # (with its own authorized-keys handling); keep ours as the only listener.
    boot.kernelParams = lib.optional orb "systemd.ssh_auto=no";

    # --- Orb boot: credentials into tmpfs, first-boot clone ---------------
    systemd.services.orb-agy-credential = lib.mkIf orb {
      description = "Copy the agy credential from the job share into ~/.gemini";
      wantedBy = ["multi-user.target"];
      unitConfig = {
        RequiresMountsFor = ["${home}/.gemini" jobMount];
        ConditionPathIsDirectory = "${jobMount}/agy";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        cp -rT ${jobMount}/agy ${home}/.gemini
        chown -R user:user ${home}/.gemini
      '';
    };

    systemd.services.orb-clone = lib.mkIf orb {
      description = "Clone the orb's repository into /home/user on first boot";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      unitConfig = {
        RequiresMountsFor = [home jobMount];
        ConditionPathExists = "${jobMount}/orb.json";
      };
      environment.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "user";
        Group = "user";
        ExecStart = lib.getExe orbClone;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    # --- Batch mode: one job, then power off ------------------------------
    systemd.services.agent-job-runner = lib.mkIf orb {
      description = "Turn the GitHub issue in /run/orb-job into a pull request";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "orb-clone.service" "orb-agy-credential.service"];
      wants = ["network-online.target"];
      unitConfig = {
        RequiresMountsFor = [home jobMount];
        ConditionPathExists = "${jobMount}/spec.md";
        SuccessAction = "poweroff";
        FailureAction = "poweroff";
      };
      environment = {
        AGENT_BACKEND = cfg.agentBackend;
        CUSTOM_AGENT_COMMAND = lib.optionalString (cfg.customAgentCommand != null) cfg.customAgentCommand;
        HOME = home;
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "user";
        Group = "user";
        ExecStart = lib.getExe runner;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };
  };
}
