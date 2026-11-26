# agent-dispatch-once --repo OWNER/REPO --issue N [--dry-run]
#
# Host side of one batch agent job, on top of the orb lifecycle:
#   1. mint a 1-hour single-repo GitHub token, fetch the issue
#   2. `orb spawn --spec` a batch orb (spec.md in its job share); the
#      orb gets its own token, CPU / memory / wall-clock limits and slot
#   3. relabel, `orb wait` until the VM powers off
#   4. relabel / comment from the status the VM wrote back, `orb delete`
#
# Exit 75 = no free orb slot; nothing was changed, retry later.
# For an interactive VM use `orb spawn OWNER/REPO` + `orb attach ID`.
#
# Environment (set by the NixOS module): RUN_DIR, TRIGGER_LABEL

usage() {
  echo "usage: agent-dispatch-once --repo OWNER/REPO --issue N [--dry-run]"
}

repo="" issue="" dry_run=false
while (($#)); do
  case "$1" in
  --repo) repo=$2 && shift 2 ;;
  --issue) issue=$2 && shift 2 ;;
  --dry-run) dry_run=true && shift ;;
  -h | --help) usage && exit 0 ;;
  *) usage >&2 && exit 64 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "agent-dispatch-once: run as root (sudo)" >&2
  exit 77
fi
if [[ -z "$repo" || -z "$issue" ]]; then
  usage >&2
  exit 64
fi

# --- 1. Credentials + issue
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

# --- 2. Spawn (the spec only lives in RAM until orb copies it into the job share)
install -d -m 0700 "$RUN_DIR"
spec=$(mktemp "$RUN_DIR/spec.XXXXXX")
id=""
cleanup() {
  rm -f "$spec"
  if [[ -n "$id" ]]; then orb delete "$id" >/dev/null || true; fi
}
trap cleanup EXIT
jq -r '"# \(.title)\n\n\(.body // "")"' <<<"$issue_json" >"$spec"

spawn_args=(--spec "$spec" --issue "$issue" --title "$title")
[[ "$dry_run" == true ]] && spawn_args+=(--dry-run)
rc=0
id=$(orb spawn "$repo" "${spawn_args[@]}") || rc=$?
if ((rc == 75)); then
  id=""
  echo "agent-dispatch-once: no free orb slot, leaving $repo#$issue for the next poll" >&2
  exit 75
elif ((rc != 0)); then
  # orb spawn already removed the half-built batch orb. The label stays,
  # so the next poll retries (e.g. after the network service is back).
  id=""
  echo "agent-dispatch-once: orb spawn failed ($rc)" >&2
  exit 1
fi

relabel "$TRIGGER_LABEL" agent-in-progress

# --- 3. Wait (the VM console lands in `journalctl -u orb-$id`)
# A failed wait must still end in agent-failed, not a stuck agent-in-progress.
result=$(orb wait "$id") || result='{"status": "orb wait failed"}'

# --- 4. Report back
status=$(jq -r '.status // "none (timeout or crash)"' <<<"$result")
pr_url=$(jq -r '.pr_url // empty' <<<"$result")
clarification=$(jq -r '.clarification // empty' <<<"$result")
echo "agent-dispatch-once: orb $id exit status: $status"
if [[ "$status" == 0 && ("$dry_run" == true || -n "$pr_url") ]]; then
  relabel agent-in-progress agent-completed
  if [[ "$dry_run" == false && -n "$pr_url" ]]; then
    gh issue comment "$issue" --repo "$repo" --body "Agent opened $pr_url" >/dev/null
  fi
elif [[ "$status" == 10 ]]; then
  relabel agent-in-progress agent-needs-clarification
  if [[ "$dry_run" == false ]]; then
    body="Agent marked this issue as needing clarification:"
    if [[ -n "$clarification" ]]; then
      body+=$'\n\n'"$clarification"
    fi
    gh issue comment "$issue" --repo "$repo" --body "$body" >/dev/null
  fi
  exit 0
else
  relabel agent-in-progress agent-failed
  if [[ "$dry_run" == false ]]; then
    gh issue comment "$issue" --repo "$repo" \
      --body "Agent run failed (status: $status). See \`journalctl -u orb-$id\` on the host." >/dev/null
  fi
  exit 1
fi
