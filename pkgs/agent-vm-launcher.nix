# Boot a microvm.nix guest: start one virtiofsd per share, then the VMM.
#
# microvm.nix's runner only starts cloud-hypervisor; the virtiofs daemons
# have to exist first. This wrapper starts them as the calling user in a
# throwaway state dir (or $AGENT_VM_STATE_DIR) and cleans up on exit.
{
  lib,
  writeShellApplication,
  virtiofsd,
  coreutils,
  name,
  vm, # a nixosSystem with the microvm module
}: let
  mc = vm.config.microvm;
  shares = builtins.filter (s: s.proto == "virtiofs") mc.shares;

  startShare = s: ''
    virtiofsd \
      --socket-path=${lib.escapeShellArg s.socket} \
      --shared-dir=${lib.escapeShellArg s.source} \
      ${lib.optionalString s.readOnly "--readonly"} \
      --sandbox=none \
      --cache=auto \
      >virtiofsd-${s.tag}.log 2>&1 &
    pids+=($!)
    socks+=(${lib.escapeShellArg s.socket})
  '';
in
  writeShellApplication {
    inherit name;
    runtimeInputs = [virtiofsd coreutils];
    text = ''
      if [ -n "''${AGENT_VM_STATE_DIR:-}" ]; then
        state=$AGENT_VM_STATE_DIR
        mkdir -p "$state"
        own_state=0
      else
        state=$(mktemp -d -t ${name}.XXXXXX)
        own_state=1
      fi
      cd "$state"

      pids=()
      socks=()
      cleanup() {
        kill "''${pids[@]}" 2>/dev/null || true
        rm -f "''${socks[@]}"
        if [ "$own_state" = 1 ]; then rm -rf "$state"; fi
      }
      trap cleanup EXIT

      ${lib.concatMapStrings startShare shares}

      for s in "''${socks[@]}"; do
        for _ in $(seq 50); do
          [ -S "$s" ] && break
          sleep 0.1
        done
        if [ ! -S "$s" ]; then
          echo "virtiofsd for $s failed to start:" >&2
          cat virtiofsd-*.log >&2
          exit 1
        fi
      done

      echo "${name}: virtiofsd pids ''${pids[*]}, state dir $state"
      echo "${name}: type 'poweroff' in the guest to exit"
      ${mc.declaredRunner}/bin/microvm-run
    '';
  }
