# orb: pausable per-repo agent microVMs on homelab (ADR-0006).
#
# An orb = one ZFS dataset (the guest's /home/user) + a state-table entry.
# A running orb additionally holds one of K slots: a pre-evaluated worker VM
# whose share paths, TAP, IP and vsock CID are fixed per slot. Pausing powers
# the guest off and frees the slot; the dataset stays.
#
# Environment (set by the NixOS module):
#   ORB_SLOTS_JSON   {"<N>": {launcher, slotDir, jobDir, workspaceDir,
#                    stateDir, vsockSocket}}, generated from the evaluated
#                    slot VMs (agentWorker.derived), the only source of
#                    per-slot paths
#   ORB_RUN_DIR      lock + results of finished orbs (tmpfs)
#   ORB_STATE_ROOT   state/, ssh/, agy-cred/ (persistent)
#   ZFS_PARENT ZFS_QUOTA VM_USER VM_UID VM_GID MEMORY_MAX CPU_QUOTA
#   TIMEOUT_SECONDS GITHUB_APP(0|1) AGY_REPOS LLM_API_KEY_FILE
#   LLM_API_KEY_ENV SSH_PROXY (systemd-ssh-proxy)
#
# A batch orb (--spec) is ephemeral: it gets TIMEOUT_SECONDS of wall clock,
# cannot be resumed, and is deleted by its caller. Interactive orbs have no
# wall-clock limit.

usage() {
  cat <<'EOF'
usage: orb spawn OWNER/REPO [--branch B]           id = repo name
       orb spawn ID                      resume a paused orb (running: no-op)
       orb pause ID                      guest poweroff, keep the workspace
       orb delete ID                     stop, destroy the dataset, forget it
       orb list
       orb attach ID [ssh args, e.g. -L 8080:localhost:8080]
       orb wait ID                       block until stopped, print result JSON
       orb refresh-tokens                re-mint GitHub tokens of running orbs
       orb gc                            expire idle orbs, purge trash, reap orphans
batch (used by agent-dispatch-once):
       orb spawn OWNER/REPO --spec FILE --issue N --title T [--dry-run]
EOF
}

RUN=$ORB_RUN_DIR
STATE=$ORB_STATE_ROOT/state
SSH_KEY=$ORB_STATE_ROOT/ssh/id_ed25519
AGY_CRED=$ORB_STATE_ROOT/agy-cred
RESULTS=$RUN/results
SELF=$(readlink -f "$0")
PAUSE_TIMEOUT=60
# GC (ADR-0006): interactive orbs paused this long go to the trash dataset;
# trash older than TRASH_DAYS is destroyed.
EXPIRE_DAYS=14
TRASH_DAYS=7
TRASH=$ZFS_PARENT-trash

die() {
  echo "orb: $*" >&2
  exit 1
}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- Slots (paths come from the evaluated VMs, never derived here) --------
max_slot() { jq -r 'keys | map(tonumber) | max' "$ORB_SLOTS_JSON"; }
slot_get() { jq -er --arg n "$1" --arg k "$2" '.[$n][$k]' "$ORB_SLOTS_JSON"; }

# --- State table: /persist/orbs/state/<id>.json ---------------------------
valid_id() { [[ $1 =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]]; }
state_file() { echo "$STATE/$1.json"; }
exists() { [[ -f "$(state_file "$1")" ]]; }
get() { jq -r --arg k "$2" '.[$k] // empty' "$(state_file "$1")"; }
is_running() { [[ "$(get "$1" state)" == running ]]; }
is_batch() { [[ "$(get "$1" mode)" == batch ]]; }
ds_exists() { zfs list -H -o name "$1" >/dev/null 2>&1; }
# put ID JQ-FILTER [jq args...]: atomic read-modify-write (caller holds lock)
put() {
  local f tmp
  f=$(state_file "$1")
  tmp=$(mktemp "$STATE/.tmp.XXXXXX")
  if [[ -f "$f" ]]; then
    jq "${@:3}" "$2" "$f" >"$tmp"
  else
    jq -n "${@:3}" "$2" >"$tmp"
  fi
  mv -f "$tmp" "$f"
}

# One lock for slot allocation and every state-table write. Never hold it
# while waiting for a unit to stop: the unit's ExecStopPost (finalize) needs
# it, so that would deadlock until the timeout.
lock() {
  exec 9>"$RUN/lock"
  flock 9
}
unlock() { exec 9>&-; }

unit_alive() {
  case "$(systemctl is-active "orb-$1" 2>/dev/null || true)" in
  active | activating | deactivating | reloading | refreshing) return 0 ;;
  *) return 1 ;;
  esac
}

# Release everything a running orb holds on the host. Idempotent; also the
# recovery path for entries left "running" by a host reboot or a crash.
finalize_locked() {
  local id=$1 slot job ws f
  exists "$id" || return 0
  slot=$(get "$id" slot)
  if [[ -n "$slot" ]]; then
    job=$(slot_get "$slot" jobDir)
    ws=$(slot_get "$slot" workspaceDir)
    # Keep the batch result for `orb wait`; everything else (tokens!) goes.
    if [[ -e "$job/status" || -e "$job/pr_url" || -e "$job/clarification.md" ]]; then
      install -d -m 0700 "$RESULTS/$id"
      for f in status pr_url clarification.md; do
        if [[ -f "$job/$f" ]]; then cp "$job/$f" "$RESULTS/$id/$f"; fi
      done
    fi
    if [[ -d "$job" ]]; then find "$job" -mindepth 1 -delete; fi
    if [[ -d "$(slot_get "$slot" stateDir)" ]]; then
      find "$(slot_get "$slot" stateDir)" -mindepth 1 -delete
    fi
    if mountpoint -q "$ws"; then umount "$ws" || umount -l "$ws"; fi
  fi
  if is_running "$id"; then
    put "$id" '.state = "paused" | .slot = null | .paused_at = $t' --arg t "$(now)"
  fi
}

reconcile_locked() {
  local f id
  for f in "$STATE"/*.json; do
    id=$(basename "$f" .json)
    if is_running "$id" && ! unit_alive "$id"; then
      finalize_locked "$id"
    fi
  done
}

reconcile() {
  lock
  reconcile_locked
  unlock
}

# Space-padded (" 1 3 ") so slot_used can match " N " without hitting 11 for 1.
used_slots_locked() { echo " $(jq -rs 'map(select(.state == "running") | .slot) | join(" ")' "$STATE"/*.json /dev/null) "; }

# slot_used N USED: USED is the output of used_slots_locked.
slot_used() { [[ "$2" == *" $1 "* ]]; }

free_slot_locked() {
  local n used
  used=$(used_slots_locked)
  for ((n = 1; n <= $(max_slot); n++)); do
    if ! slot_used "$n" "$used"; then
      echo "$n"
      return 0
    fi
  done
  return 1
}

# --- Host resources ---------------------------------------------------------
ensure_host() {
  local ds
  install -d -m 0755 "$RUN"
  install -d -m 0700 "$ORB_STATE_ROOT" "$STATE" "$(dirname "$SSH_KEY")" "$RESULTS"
  if [[ ! -f "$SSH_KEY" ]]; then
    ssh-keygen -q -t ed25519 -N "" -C "orb-host" -f "$SSH_KEY"
  fi
  # Parent is never mounted; children are mountpoint=legacy and mounted
  # only at a slot's workspace path while the orb runs.
  for ds in "$ZFS_PARENT" "$TRASH"; do
    if ! ds_exists "$ds"; then zfs create -o mountpoint=none "$ds"; fi
  done
}

# write_secret FILE: stdin -> FILE (0400, agent-vm) via rename, so the guest
# never reads a half-written token.
write_secret() {
  local tmp
  tmp=$(mktemp "$(dirname "$1")/.tmp.XXXXXX")
  cat >"$tmp"
  chown "$VM_USER:$VM_USER" "$tmp"
  chmod 0400 "$tmp"
  mv -f "$tmp" "$1"
}

mint_token() {
  [[ "$GITHUB_APP" == 1 ]] || return 1
  mint-github-app-token "$1"
}

# prepare_slot ID SLOT [SPEC ISSUE TITLE DRY_RUN]: slot dirs, workspace
# mount and job files for orb ID. A SPEC makes it a batch job.
prepare_slot() {
  local id=$1 slot=$2 spec=${3:-} issue=${4:-} title=${5:-} dry_run=${6:-false}
  local repo branch job ws vm mode=interactive new_ds=0 token agy_src
  [[ -z "$spec" ]] || mode="batch"
  repo=$(get "$id" repo)
  branch=$(get "$id" branch)
  job=$(slot_get "$slot" jobDir)
  ws=$(slot_get "$slot" workspaceDir)
  vm=$(slot_get "$slot" stateDir)

  install -d -m 0755 "$(dirname "$(slot_get "$slot" slotDir)")"
  install -d -m 0700 -o "$VM_USER" -g "$VM_USER" "$(slot_get "$slot" slotDir)" "$job" "$ws" "$vm"
  find "$job" "$vm" -mindepth 1 -delete

  if mountpoint -q "$ws"; then die "slot $slot workspace is still mounted"; fi
  if ! ds_exists "$ZFS_PARENT/$id"; then
    zfs create -o mountpoint=legacy -o "quota=$ZFS_QUOTA" "$ZFS_PARENT/$id"
    new_ds=1
  fi
  mount -t zfs "$ZFS_PARENT/$id" "$ws"
  if ((new_ds)); then
    chown "$VM_UID:$VM_GID" "$ws"
    chmod 0700 "$ws"
  fi

  jq -n --arg id "$id" --arg repo "$repo" --arg branch "$branch" \
    --arg mode "$mode" --arg issue "$issue" --arg title "$title" \
    --argjson dry "$dry_run" --arg env "$LLM_API_KEY_ENV" \
    '{id: $id, repo: $repo, branch: (if $branch == "" then null else $branch end), mode: $mode}
     + if $mode == "batch" then {issue_number: ($issue | tonumber), issue_title: $title,
                                 dry_run: $dry, llm_api_key_env: $env} else {} end' \
    >"$job/orb.json"
  write_secret "$job/authorized_keys" <"$SSH_KEY.pub"

  if token=$(mint_token "$repo"); then
    printf '%s' "$token" | write_secret "$job/github_token"
  elif [[ "$GITHUB_APP" == 1 ]]; then
    [[ "$mode" == batch ]] && die "cannot mint a GitHub token for $repo"
    echo "orb: warning: cannot mint a GitHub token for $repo; orb has no push access" >&2
  fi

  if [[ " $AGY_REPOS " == *" $repo "* ]]; then
    # Accept either raw ~/.gemini contents or a HOME dir (e.g. `HOME=/persist/orbs/agy-cred agy`).
    agy_src=$AGY_CRED
    if [[ -d "$AGY_CRED/.gemini" ]]; then agy_src=$AGY_CRED/.gemini; fi
    if [[ -n "$(ls -A "$agy_src" 2>/dev/null)" ]]; then
      cp -r "$agy_src" "$job/agy"
      chown -R "$VM_USER:$VM_USER" "$job/agy"
      chmod -R u=rwX,go= "$job/agy"
    else
      echo "orb: warning: $agy_src is empty; agy will not be logged in" >&2
    fi
  fi

  if [[ "$mode" == batch ]]; then
    install -m 0400 -o "$VM_USER" -g "$VM_USER" "$spec" "$job/spec.md"
    if [[ -n "$LLM_API_KEY_FILE" ]]; then
      write_secret "$job/llm_api_key" <"$LLM_API_KEY_FILE"
    fi
  fi
  chown "$VM_USER:$VM_USER" "$job/orb.json"
  chmod 0400 "$job/orb.json"
}

start_unit() {
  local id=$1 slot=$2 vm args
  vm=$(slot_get "$slot" stateDir)
  # Fail closed: no firewall table, no VM.
  if ! nft list table inet agent-isolation >/dev/null 2>&1; then
    die "nft table agent-isolation missing; refusing to boot"
  fi
  systemctl reset-failed "orb-$id" >/dev/null 2>&1 || true
  args=(
    --unit="orb-$id" --collect --quiet
    --uid="$VM_USER" --gid="$VM_USER"
    -p SupplementaryGroups=kvm
    -p WorkingDirectory="$vm"
    -p MemoryMax="$MEMORY_MAX"
    -p CPUQuota="$CPU_QUOTA"
    -E AGENT_VM_STATE_DIR="$vm"
    # "+" runs the cleanup as root although the unit runs as agent-vm. It
    # fires however the VM ends: guest poweroff, crash, timeout, stop.
    -p "ExecStopPost=+$SELF _finalize $id"
  )
  # Interactive orbs live for days; only batch ones get a deadline.
  if is_batch "$id"; then
    args+=(-p RuntimeMaxSec="$TIMEOUT_SECONDS")
  fi
  systemd-run "${args[@]}" "$(slot_get "$slot" launcher)"
}

# --- Commands ---------------------------------------------------------------
# EXIT trap of a failed spawn: free the slot; a batch orb is useless
# afterwards, so it goes entirely (the caller only learns its id on success).
spawn_abort() {
  finalize_locked "$spawn_id"
  if is_batch "$spawn_id"; then
    if ds_exists "$ZFS_PARENT/$spawn_id"; then zfs destroy -r "$ZFS_PARENT/$spawn_id" || true; fi
    rm -f "$(state_file "$spawn_id")"
  fi
}

spawn_id=""

cmd_spawn() {
  local target="" branch="" spec="" issue="" title="" dry_run=false mode=interactive id repo="" slot
  while (($#)); do
    case "$1" in
    --branch) branch=$2 && shift 2 ;;
    --spec) spec=$2 mode="batch" && shift 2 ;;
    --issue) issue=$2 && shift 2 ;;
    --title) title=$2 && shift 2 ;;
    --dry-run) dry_run=true && shift ;;
    -*) usage >&2 && exit 64 ;;
    *)
      if [[ -n "$target" ]]; then usage >&2 && exit 64; fi
      target=$1 && shift
      ;;
    esac
  done
  [[ -n "$target" ]] || { usage >&2 && exit 64; }
  if [[ "$mode" == batch ]]; then
    [[ -f "$spec" && "$issue" =~ ^[0-9]+$ ]] || die "batch spawn needs --spec FILE and a numeric --issue"
  elif [[ -n "$issue$title" || "$dry_run" == true ]]; then
    die "--issue, --title and --dry-run need --spec"
  fi
  [[ -z "$branch" || ("$branch" =~ ^[A-Za-z0-9._/-]+$ && "$branch" != -*) ]] ||
    die "invalid branch: $branch"

  if [[ "$target" == */* ]]; then
    repo=$target
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid repo: $repo"
    id=$(tr '[:upper:]' '[:lower:]' <<<"${repo#*/}" | tr -c 'a-z0-9\n' '-' | sed 's/^-*//' | cut -c1-32)
    if [[ "$mode" == batch ]]; then id="$id-i$issue"; fi
  else
    id=$target
    [[ -z "$branch" && "$mode" == interactive ]] || die "resume takes no options: orb spawn $id"
  fi
  valid_id "$id" || die "invalid orb id: $id"

  ensure_host
  lock
  reconcile_locked
  if exists "$id"; then
    if [[ -n "$repo" && ("$(get "$id" repo)" != "$repo" || "$(get "$id" branch)" != "$branch") ]]; then
      die "orb $id already exists for $(get "$id" repo) branch '$(get "$id" branch)'"
    fi
    if is_running "$id"; then
      unlock
      echo "$id"
      return 0
    fi
    # Its spec is gone; a resumed batch orb would be an interactive one
    # with a batch deadline.
    if [[ -z "$repo" ]] && is_batch "$id"; then die "orb $id is a finished batch orb; delete it"; fi
  elif [[ -z "$repo" ]]; then
    die "no such orb: $id"
  fi

  if ! slot=$(free_slot_locked); then
    echo "orb: no free slot (max $(max_slot) running)" >&2
    exit 75
  fi

  if ! exists "$id"; then
    put "$id" '{id: $id, repo: $repo, branch: (if $b == "" then null else $b end),
                slot: null, state: "paused", created: $t, paused_at: null, mode: $m}' \
      --arg id "$id" --arg repo "$repo" --arg b "$branch" --arg t "$(now)" --arg m "$mode"
  fi
  put "$id" '.state = "running" | .slot = $s' --argjson s "$slot"
  # Any failure from here on must give the slot back (we still hold the lock).
  spawn_id=$id
  trap spawn_abort EXIT
  prepare_slot "$id" "$slot" "$spec" "$issue" "$title" "$dry_run"
  start_unit "$id" "$slot"
  trap - EXIT
  unlock
  echo "$id"
}

cmd_pause() {
  local id=${1:?usage: orb pause ID} i
  exists "$id" || die "no such orb: $id"
  if unit_alive "$id"; then
    timeout 15 "$SELF" _ssh "$id" -- sudo poweroff >/dev/null 2>&1 || true
    for ((i = 0; i < PAUSE_TIMEOUT; i++)); do
      unit_alive "$id" || break
      sleep 1
    done
    if unit_alive "$id"; then
      echo "orb: $id did not power off within ${PAUSE_TIMEOUT}s; stopping" >&2
      systemctl stop "orb-$id"
    fi
  fi
  reconcile
  echo "$id paused"
}

# The liveness check must happen under the lock: outside it a concurrent
# `orb spawn ID` can start the unit, and zfs destroy then hits a mounted
# dataset. The stop itself runs unlocked (finalize needs the lock).
cmd_delete() {
  local id=${1:?usage: orb delete ID}
  valid_id "$id" || die "invalid orb id: $id"
  lock
  reconcile_locked
  if unit_alive "$id"; then
    unlock
    systemctl stop "orb-$id" || true
    lock
    reconcile_locked
    if unit_alive "$id"; then die "orb $id is still running; not deleting"; fi
  fi
  if ds_exists "$ZFS_PARENT/$id"; then zfs destroy -r "$ZFS_PARENT/$id"; fi
  rm -f "$(state_file "$id")"
  rm -rf "${RESULTS:?}/$id"
  unlock
  echo "$id deleted"
}

cmd_list() {
  reconcile
  {
    echo "ID REPO BRANCH STATE SLOT CREATED PAUSED_AT MODE"
    jq -r '[.id, .repo, .branch // "-", .state, .slot // "-", .created,
            .paused_at // "-", .mode] | @tsv' "$STATE"/*.json /dev/null
  } | column -t
}

# ssh ID [ssh args] [-- remote command]: ssh as `user` into a running orb
# over cloud-hypervisor's hybrid vsock. systemd-ssh-proxy understands the
# "vsock-mux/<unix socket>" host form (it does CH's "CONNECT 22" handshake)
# and hands ssh the fd.
cmd_ssh() {
  local id=${1:?} slot opts=() remote=()
  shift
  slot=$(get "$id" slot)
  if [[ -z "$slot" ]] || ! unit_alive "$id"; then die "orb $id is not running"; fi
  while (($#)); do
    if [[ "$1" == -- ]]; then
      shift
      remote=("$@")
      break
    fi
    opts+=("$1") && shift
  done
  # Host keys are regenerated on every boot (tmpfs root) and the transport
  # is a root-only local socket, so there is nothing to pin.
  exec ssh -i "$SSH_KEY" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o ProxyCommand="$SSH_PROXY %h %p" -o ProxyUseFdpass=yes \
    "${opts[@]}" "user@vsock-mux$(slot_get "$slot" vsockSocket)" "${remote[@]}"
}

cmd_attach() {
  local id=${1:?usage: orb attach ID [ssh args]}
  shift
  exists "$id" || die "no such orb: $id"
  cmd_ssh "$id" -t "$@" -- tmux new-session -A -s main
}

cmd_wait() {
  local id=${1:?usage: orb wait ID}
  exists "$id" || die "no such orb: $id"
  while unit_alive "$id"; do sleep 5; done
  reconcile
  jq -n --arg s "$(cat "$RESULTS/$id/status" 2>/dev/null || true)" \
    --arg p "$(cat "$RESULTS/$id/pr_url" 2>/dev/null || true)" \
    --arg c "$(cat "$RESULTS/$id/clarification.md" 2>/dev/null || true)" \
    '{status: (if $s == "" then null else ($s | rtrimstr("\n")) end),
      pr_url: (if $p == "" then null else ($p | rtrimstr("\n")) end),
      clarification: (if $c == "" then null else ($c | rtrimstr("\n")) end)}'
}

cmd_refresh_tokens() {
  local f id repo slot token
  [[ "$GITHUB_APP" == 1 ]] || return 0
  for f in "$STATE"/*.json; do
    id=$(basename "$f" .json)
    is_running "$id" || continue
    repo=$(get "$id" repo)
    slot=$(get "$id" slot)
    if ! token=$(mint_token "$repo"); then
      echo "orb: cannot re-mint token for $id ($repo)" >&2
      continue
    fi
    lock
    # The orb may have stopped while we were minting; never write a token
    # into a slot that is now free or belongs to another orb.
    if is_running "$id" && [[ "$(get "$id" slot)" == "$slot" ]]; then
      printf '%s' "$token" | write_secret "$(slot_get "$slot" jobDir)/github_token"
    fi
    unlock
  done
}

# Grace copy instead of a snapshot: destroying a dataset destroys its
# snapshots, so an expired or orphaned dataset is renamed into $TRASH with
# its trash time as suffix. Restore: zfs rename $TRASH/ID-EPOCH $ZFS_PARENT/ID
# to_trash ID EPOCH REASON
to_trash() {
  zfs rename "$ZFS_PARENT/$1" "$TRASH/$1-$2" &&
    echo "orb gc: $3 $1 -> $TRASH/$1-$2"
}

ds_children() { zfs list -H -o name -d 1 -t filesystem "$1" | sed -n "s|^$1/||p"; }

cmd_gc() {
  local f id unit paused_at trashed trashed_at slot used ws dir unit_left=0 epoch
  epoch=$(date +%s)
  ensure_host
  lock
  reconcile_locked
  # Transient orb-<id> units nobody owns. Static units are named orbs-* and
  # are not transient either; the Transient check is defence in depth. Stopped unlocked: their ExecStopPost takes the lock.
  local orphans=()
  while read -r unit _; do
    id=${unit#orb-} id=${id%.service}
    if ! exists "$id" && [[ "$(systemctl show -P Transient "$unit")" == yes ]] && unit_alive "$id"; then
      orphans+=("$id")
    fi
  done < <(systemctl list-units --plain --no-legend --type=service 'orb-*')
  unlock
  for id in "${orphans[@]}"; do
    echo "orb gc: stopping orphan unit orb-$id"
    systemctl stop "orb-$id" || true
    if unit_alive "$id"; then unit_left=1; fi
  done

  lock
  reconcile_locked
  for f in "$STATE"/*.json; do
    id=$(basename "$f" .json)
    paused_at=$(get "$id" paused_at)
    if [[ "$(get "$id" state)" == paused && "$(get "$id" mode)" == interactive && -n "$paused_at" ]] &&
      (($(date -d "$paused_at" +%s) < epoch - EXPIRE_DAYS * 86400)); then
      if ds_exists "$ZFS_PARENT/$id"; then to_trash "$id" "$epoch" "expired (paused since $paused_at)" || continue; fi
      rm -f "$f"
      rm -rf "${RESULTS:?}/$id"
    fi
  done

  for trashed in $(ds_children "$TRASH"); do
    trashed_at=${trashed##*-}
    if [[ "$trashed_at" =~ ^[0-9]+$ ]] && ((trashed_at < epoch - TRASH_DAYS * 86400)); then
      zfs destroy -r "$TRASH/$trashed" && echo "orb gc: purged $TRASH/$trashed"
    fi
  done

  # An orphan VM that would not stop may still use any free slot and its
  # dataset, so nothing below is safe.
  if ((unit_left)); then
    unlock
    die "gc: an orphan unit is still running; slots and datasets not reaped"
  fi

  # Free slots: leftovers of a crash.
  used=$(used_slots_locked)
  for ((slot = 1; slot <= $(max_slot); slot++)); do
    ! slot_used "$slot" "$used" || continue
    ws=$(slot_get "$slot" workspaceDir)
    if mountpoint -q "$ws"; then umount "$ws" || umount -l "$ws"; fi
    for dir in "$(slot_get "$slot" jobDir)" "$(slot_get "$slot" stateDir)"; do
      if [[ -d "$dir" ]]; then find "$dir" -mindepth 1 -delete; fi
    done
  done

  # Datasets with no state entry, e.g. a crash mid-spawn: may hold real
  # work, so trash, never destroy.
  for id in $(ds_children "$ZFS_PARENT"); do
    exists "$id" || to_trash "$id" "$epoch" "orphan dataset" || true
  done
  unlock
}

# --- Main -------------------------------------------------------------------
shopt -s nullglob
if [[ $EUID -ne 0 ]]; then
  echo "orb: run as root (sudo)" >&2
  exit 77
fi

cmd=${1:-}
shift || true
case "$cmd" in
spawn) cmd_spawn "$@" ;;
pause) cmd_pause "$@" ;;
delete) cmd_delete "$@" ;;
list | ls) cmd_list ;;
attach) cmd_attach "$@" ;;
wait) cmd_wait "$@" ;;
refresh-tokens) cmd_refresh_tokens ;;
gc) cmd_gc ;;
_ssh) cmd_ssh "$@" ;;
_finalize)
  lock
  finalize_locked "${1:?}"
  unlock
  ;;
_boot)
  ensure_host
  reconcile
  ;;
-h | --help | help) usage ;;
*) usage >&2 && exit 64 ;;
esac
