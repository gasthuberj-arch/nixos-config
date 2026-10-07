{
  lib,
  pkgs,
  ...
}: let
  # ssh-agent runs its SSH_ASKPASS for every signature with a key added
  # under a confirm constraint (ssh-add -c / AddKeysToAgent confirm) and
  # sets SSH_ASKPASS_PROMPT=confirm; exit 0 means allow. A click-to-confirm
  # dialog would not gate anything here: any Wayland client can inject
  # keystrokes via virtual-keyboard, so only the finger proves presence.
  fingerprintConfirm = pkgs.writeShellApplication {
    name = "ssh-askpass-fingerprint";
    runtimeInputs = with pkgs; [coreutils fprintd gnugrep libnotify util-linux];
    text = ''
      # Never answer a passphrase prompt: this program must not hand out secrets.
      if [ "''${SSH_ASKPASS_PROMPT:-}" != confirm ]; then
        exit 1
      fi

      notify() {
        # -p prints a new id, -r replaces that notification in place, so the
        # attempt counter updates one popup instead of stacking them.
        local out
        out=$(notify-send -p ''${id:+-r "$id"} -a ssh-agent "$@" || true)
        id=''${out:-''${id:-}}
      }

      # The notification is a convenience, not a control: any process running
      # as this user can suppress it (dunstctl set-paused, its own dunstctl
      # reload, or just killing dunst). The journal line is the part that
      # survives that, so an unexplained touch request can be traced after the
      # fact. The gate itself is the fingerprint, which none of that bypasses.
      logger -t ssh-askpass-fingerprint "key use requested: ''${1:-no detail}"

      id=""
      notify -u critical -t 30000 \
        "Touch the fingerprint sensor to allow SSH key use" "''${1:-}"

      # A single bad read (dry finger, partial swipe) must not fail the push:
      # ssh gives up the moment the agent refuses, with no retry of its own.
      # fprintd-verify already loops over retry-scan results, but reports a
      # non-matching read as a final no-match, so the retry belongs here.
      rc=1
      for attempt in 1 2 3; do
        # ssh-agent is single-threaded and blocks while this runs, so bound
        # each attempt. -f any: without it fprintd-verify checks only the
        # first enrolled finger, so a backup finger always reads no-match.
        vrc=0
        out=$(timeout 20 fprintd-verify -f any 2>&1) || vrc=$?

        # Exit status alone is enough on fprintd 1.94; the grep keeps a future
        # regression there from failing open.
        if [ "$vrc" -eq 0 ] && grep -q '^Verify result: verify-match' <<<"$out"; then
          rc=0
          break
        fi

        # 124: nothing touched the sensor within the timeout, so nobody is
        # waiting to retry. Stop rather than burn the remaining attempts -
        # timeout kills fprintd-verify mid-verify, which leaves the device
        # claimed, and every retry would fail instantly with AlreadyInUse.
        if [ "$vrc" -eq 124 ] || [ "$attempt" -eq 3 ]; then
          break
        fi

        msg="No match, touch again ($attempt/3)"
        grep -q AlreadyInUse <<<"$out" && msg="Sensor busy, retrying ($attempt/3)"
        notify -u critical -t 30000 "$msg" "''${1:-}"
      done

      result=denied
      [ "$rc" -eq 0 ] && result=allowed
      logger -t ssh-askpass-fingerprint "key use $result"
      notify -t 3000 "SSH key use $result"
      exit "$rc"
    '';
  };
in {
  # With fprintd enabled, NixOS adds pam_fprintd to every PAM service by
  # default. Keep the touch meaning exactly one thing: a sensor read carries
  # no statement of what it was for, so a second consumer of it can take a
  # touch meant for a push. Nothing on this host reaches those PAM stacks
  # today (wheel is NOPASSWD in core/base.nix and no polkit agent runs), so
  # this is about what a later service would silently inherit. Extending the
  # submodule type sets the default on every service, including ones added
  # later; a service can still opt back in explicitly.
  options.security.pam.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config.fprintAuth = lib.mkDefault false;
    });
  };

  config = {
    services.fprintd.enable = true;

    # OpenSSH's own agent instead of gnome-keyring's (NixOS allows only one).
    # gcr-ssh-agent offers to save key passphrases in the login keyring,
    # which any process running as johannes can read over D-Bus.
    services.gnome.gcr-ssh-agent.enable = false;

    programs.ssh.startAgent = true;
    # Already false by default here (it follows services.xserver.enable), but
    # pinned: turning it on would export SSH_ASKPASS to every session, where
    # ssh and git would route passphrase prompts to a fingerprint check that
    # is only meant to answer the agent's confirm.
    programs.ssh.enableAskPassword = false;
    systemd.user.services.ssh-agent.environment.SSH_ASKPASS =
      lib.mkForce (lib.getExe fingerprintConfirm);

    # A restart wipes every loaded key, so a rebuild that touches this unit
    # would cost re-entering both passphrases. Changes here take effect at
    # the next login instead.
    systemd.user.services.ssh-agent.restartIfChanged = false;
  };
}
