# Runs once, as `user`, inside a batch orb: the host dropped spec.md into
# /run/orb-job (virtiofs share). Turns one GitHub issue into one PR.
#
# Inputs (all written by the host, never baked into /nix/store):
#   /run/orb-job/orb.json      {id, repo, branch, mode: "batch", issue_number, issue_title, dry_run?, branch_name?, llm_api_key_env?}
#   /run/orb-job/spec.md       rendered issue body
#   /run/orb-job/github_token  short-lived single-repo token, rewritten by the
#                              host; git and gh re-read it on every call
#   /run/orb-job/llm_api_key   optional API key for API-billed backends
#
# The repo was cloned into ~/<repo name> by orb-clone.service (branch
# orb.json .branch); the work branch is created from it here.
#
# Environment (set by the NixOS module):
#   AGENT_BACKEND         antigravity | claude-code | opencode | aider | custom
#   CUSTOM_AGENT_COMMAND  shell command used when AGENT_BACKEND=custom
#
# Outputs: /run/orb-job/status (exit code), /run/orb-job/pr_url

JOB_DIR=/run/orb-job
SPEC_FILE="$JOB_DIR/spec.md"

write_status() {
  local rc=$?
  echo "$rc" >"$JOB_DIR/status" || true
  echo "agent-job-runner: finished with exit code $rc"
}
trap write_status EXIT

field() { jq -r "$1" "$JOB_DIR/orb.json"; }

repo=$(field '.repo')
issue=$(field '.issue_number')
title=$(field '.issue_title')
branch=$(field ".branch_name // \"agent/issue-$issue\"")
dry_run=$(field '.dry_run // false')
llm_env=$(field '.llm_api_key_env // "ANTHROPIC_API_KEY"')
workspace="$HOME/$(basename "$repo")"

echo "agent-job-runner: $repo#$issue ($title) backend=$AGENT_BACKEND dry_run=$dry_run"

if [[ -s "$JOB_DIR/llm_api_key" ]]; then
  export "$llm_env=$(<"$JOB_DIR/llm_api_key")"
fi

git config --global user.name "agent-worker[bot]"
git config --global user.email "agent-worker[bot]@users.noreply.github.com"

if [[ ! -d "$workspace/.git" ]]; then
  echo "agent-job-runner: $workspace missing (orb-clone failed?)" >&2
  exit 4
fi
cd "$workspace"
if [[ "$(git branch --show-current)" != "$branch" ]]; then
  git switch -c "$branch"
fi
base_rev=$(git rev-parse HEAD)

# --- Pick the toolchain: repo devShell if it has one, guest system otherwise
wrap=()
if [[ -f flake.nix ]] && nix eval --raw ".#devShells.x86_64-linux.default.drvPath" >/dev/null 2>&1; then
  echo "agent-job-runner: using repo devShell"
  wrap=(nix develop --command)
fi

prompt="You are running non-interactively inside a disposable sandbox VM.
Implement GitHub issue #$issue of $repo. The full specification is in $SPEC_FILE.
Read AGENTS.md in the repository root first if it exists and follow it.
Then implement the specification, run the repository's checks
(nix flake check, pre-commit, or the project's test suite) and fix failures.
Finally stage and commit your changes with a descriptive message ending in 'Fixes #$issue'.
Do not push; do not open a pull request."

# --- Swappable agent adapter
export SPEC_FILE
case "$AGENT_BACKEND" in
# agy confines file access to its workspace, so the spec goes inline.
antigravity) agent=(agy -p "$prompt"$'\n\n'"$(<"$SPEC_FILE")" --dangerously-skip-permissions) ;;
claude-code) agent=(claude -p "$prompt" --dangerously-skip-permissions) ;;
opencode) agent=(opencode run "$prompt") ;;
aider) agent=(aider --yes-always --no-auto-commits --message "$prompt") ;;
custom) agent=(bash -c "$CUSTOM_AGENT_COMMAND") ;;
*)
  echo "unknown AGENT_BACKEND=$AGENT_BACKEND" >&2
  exit 2
  ;;
esac

"${wrap[@]}" "${agent[@]}"

# Commit anything the agent left uncommitted
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "$title" -m "Fixes #$issue"
fi

if [[ "$(git rev-parse HEAD)" == "$base_rev" ]]; then
  echo "agent-job-runner: agent produced no changes" >&2
  exit 3
fi

git --no-pager log --oneline "$base_rev..HEAD"
git --no-pager diff --stat "$base_rev..HEAD"

if [[ "$dry_run" == "true" ]]; then
  echo "agent-job-runner: dry run, not pushing"
  exit 0
fi

# --- Publish
git push origin "$branch"
gh pr create --repo "$repo" --head "$branch" --title "$title" \
  --body "Automated implementation of #$issue by the ephemeral microVM agent worker.

Fixes #$issue" | tee "$JOB_DIR/pr_url"
