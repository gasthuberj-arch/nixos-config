# `nix run .#agent-vm-sandbox`: boot the agent microVM interactively.
#
# microvm.nix's runner only starts cloud-hypervisor; the virtiofs daemon for
# the shared /nix/store has to exist first. This wrapper starts it as your
# own user in a throwaway state dir, boots the VM, and cleans up on exit.
{
  writeShellApplication,
  virtiofsd,
  coreutils,
  microvmRunner,
  hostName,
}:
writeShellApplication {
  name = "agent-vm-sandbox";
  runtimeInputs = [virtiofsd coreutils];
  text = ''
    state=$(mktemp -d -t agent-vm-sandbox.XXXXXX)
    cd "$state"

    sock="${hostName}-virtiofs-ro-store.sock"
    virtiofsd \
      --socket-path="$sock" \
      --shared-dir=/nix/store \
      --readonly \
      --sandbox=none \
      --cache=auto \
      >virtiofsd.log 2>&1 &
    vfs_pid=$!

    cleanup() {
      kill "$vfs_pid" 2>/dev/null || true
      rm -rf "$state"
    }
    trap cleanup EXIT

    for _ in $(seq 50); do
      [ -S "$sock" ] && break
      sleep 0.1
    done
    if [ ! -S "$sock" ]; then
      echo "virtiofsd failed to start:" >&2
      cat virtiofsd.log >&2
      exit 1
    fi

    echo "agent-vm-sandbox: virtiofsd pid $vfs_pid, state dir $state"
    echo "agent-vm-sandbox: type 'poweroff' in the guest to exit"
    ${microvmRunner}/bin/microvm-run
  '';
}
