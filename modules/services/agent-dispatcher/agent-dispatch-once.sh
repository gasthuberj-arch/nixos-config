# agent-dispatch-once --repo OWNER/REPO --issue N [--dry-run]
# agent-dispatch-once --shell
#
# Host side of one agent job:
#   1. take the global lock (one VM at a time)
#   2. mint a 1-hour single-repo GitHub token, fetch the issue
#   3. write job.json / spec.md / secrets into a RAM-only dir under /run
#   4. boot the worker VM as the unprivileged agent-vm user, inside a
#      transient systemd unit with CPU / memory / wall-clock limits
#   5. relabel the issue from the status the VM wrote back, then wipe the dir
#
# --shell boots the same VM (same network, same firewall) with an empty job
# dir, so you get an interactive root shell for poking at the isolation.
#
# Environment (set by the NixOS module): RUN_DIR, VM_USER, LAUNCHER,
# TIMEOUT_SECONDS, MEMORY_MAX, CPU_QUOTA, TRIGGER_LABEL, LLM_API_KEY_FILE,
# LLM_API_KEY_ENV

usage() {
  echo "usage: agent-dispatch-once --repo OWNER/REPO --issue N [--dry-run]"
  echo "       agent-dispatch-once --shell"
}

repo="" issue="" dry_run=false shell=false
while (($#)); do
  case "$1" in
  --repo) repo=$2 && shift 2 ;;
  --issue) issue=$2 && shift 2 ;;
  --dry-run) dry_run=true && shift ;;
  --shell) shell=true && shift ;;
  -h | --help) usage && exit 0 ;;
  *) usage >&2 && exit 64 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "agent-dispatch-once: run as root (sudo)" >&2
  exit 77
fi
if [[ "$shell" == false && (-z "$repo" || -z "$issue") ]]; then
  usage >&2
  exit 64
fi

JOB_DIR="$RUN_DIR/current-job"
STATE_DIR="$RUN_DIR/vm"

# --- 1. One VM at a time
mkdir -p "$RUN_DIR"
exec 9>"$RUN_DIR/lock"
if ! flock -n 9; then
  echo "agent-dispatch-once: another agent VM is running" >&2
  exit 75
fi

# Tokens must never outlive the VM, whatever happens below.
wipe_job_dir() { rm -rf "${JOB_DIR:?}" "${STATE_DIR:?}"; }
trap wipe_job_dir EXIT
wipe_job_dir
install -d -m 0700 -o "$VM_USER" -g "$VM_USER" "$JOB_DIR" "$STATE_DIR"

boot_vm() {
  local unit=$1
  shift
  # Fail closed: no firewall table, no VM.
  if ! nft list table inet agent-isolation >/dev/null 2>&1; then
    echo "agent-dispatch-once: nft table agent-isolation missing; refusing to boot" >&2
    exit 1
  fi
  systemd-run --unit="agent-vm-$unit" --collect --quiet --wait \
    --uid="$VM_USER" --gid="$VM_USER" \
    -p SupplementaryGroups=kvm \
    -p WorkingDirectory="$STATE_DIR" \
    -p RuntimeMaxSec="$TIMEOUT_SECONDS" \
    -p MemoryMax="$MEMORY_MAX" \
    -p CPUQuota="$CPU_QUOTA" \
    -E AGENT_VM_STATE_DIR="$STATE_DIR" \
    "$@" "$LAUNCHER"
}

if [[ "$shell" == true ]]; then
  boot_vm shell --pty
  exit 0
fi

# --- 2. Credentials + issue
GH_TOKEN=$(mint-github-app-token "$repo")
export GH_TOKEN

issue_json=$(gh api "repos/$repo/issues/$issue")
title=$(jq -r '.title' <<<"$issue_json")
echo "agent-dispatch-once: $repo#$issue \"$title\" (dry_run=$dry_run)"

relabel() {
  [[ "$dry_run" == true ]] && return 0
  gh label create "$2" --repo "$repo" --force --color ededed >/dev/null
  gh issue edit "$issue" --repo "$repo" --remove-label "$1" --add-label "$2" >/dev/null
}

# --- 3. Job dir (RAM only, readable by the VM user only)
jq -r '"# \(.title)\n\n\(.body // "")"' <<<"$issue_json" >"$JOB_DIR/spec.md"
jq -n \
  --arg repo "$repo" --argjson issue "$issue" --arg title "$title" \
  --argjson dry "$dry_run" --arg env "$LLM_API_KEY_ENV" \
  '{repo: $repo, issue_number: $issue, issue_title: $title,
    dry_run: $dry, llm_api_key_env: $env}' >"$JOB_DIR/job.json"
printf '%s' "$GH_TOKEN" >"$JOB_DIR/github_token"
if [[ -n "$LLM_API_KEY_FILE" ]]; then
  cat "$LLM_API_KEY_FILE" >"$JOB_DIR/llm_api_key"
fi
chown "$VM_USER:$VM_USER" "$JOB_DIR"/*
chmod 0400 "$JOB_DIR"/*

relabel "$TRIGGER_LABEL" agent-in-progress

# --- 4. Run the VM (its console output lands in this unit's journal)
boot_vm "issue-$issue" --pipe || true

# --- 5. Report back
status=$(cat "$JOB_DIR/status" 2>/dev/null || echo "none (timeout or crash)")
echo "agent-dispatch-once: VM exit status: $status"
if [[ "$status" == 0 ]]; then
  relabel agent-in-progress agent-completed
  if [[ "$dry_run" == false && -s "$JOB_DIR/pr_url" ]]; then
    gh issue comment "$issue" --repo "$repo" --body "Agent opened $(<"$JOB_DIR/pr_url")" >/dev/null
  fi
else
  relabel agent-in-progress agent-failed
  if [[ "$dry_run" == false ]]; then
    gh issue comment "$issue" --repo "$repo" \
      --body "Agent run failed (status: $status). See \`journalctl -u agent-dispatcher\` on the host." >/dev/null
  fi
  exit 1
fi
