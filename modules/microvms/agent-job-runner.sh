# Runs once inside the agent microVM when the host has dropped a job into
# /run/agent-job (virtiofs share). Turns one GitHub issue into one PR.
#
# Inputs (all written by the host dispatcher, never baked into /nix/store):
#   /run/agent-job/job.json      {repo, issue_number, issue_title, branch_name?, dry_run?, llm_api_key_env?}
#   /run/agent-job/spec.md       rendered issue body
#   /run/agent-job/github_token  1-hour, single-repo GitHub App installation token
#   /run/agent-job/llm_api_key   API key for the coding agent CLI
#
# Environment (set by the NixOS module):
#   AGENT_BACKEND         claude-code | opencode | aider | custom
#   CUSTOM_AGENT_COMMAND  shell command used when AGENT_BACKEND=custom
#
# Outputs: /run/agent-job/status (exit code), /run/agent-job/pr_url

JOB_DIR=/run/agent-job
SPEC_FILE="$JOB_DIR/spec.md"
WORKSPACE=/tmp/workspace/repo

write_status() {
  local rc=$?
  echo "$rc" >"$JOB_DIR/status" || true
  echo "agent-job-runner: finished with exit code $rc"
}
trap write_status EXIT

field() { jq -r "$1" "$JOB_DIR/job.json"; }

repo=$(field '.repo')
issue=$(field '.issue_number')
title=$(field '.issue_title')
branch=$(field ".branch_name // \"agent/issue-$issue\"")
dry_run=$(field '.dry_run // false')
llm_env=$(field '.llm_api_key_env // "ANTHROPIC_API_KEY"')

echo "agent-job-runner: $repo#$issue ($title) backend=$AGENT_BACKEND dry_run=$dry_run"

# --- Credentials: read from the RAM-only share, exported only to this process tree
GH_TOKEN=$(<"$JOB_DIR/github_token")
export GH_TOKEN
if [[ -s "$JOB_DIR/llm_api_key" ]]; then
  export "$llm_env=$(<"$JOB_DIR/llm_api_key")"
fi

git config --global user.name "agent-worker[bot]"
git config --global user.email "agent-worker[bot]@users.noreply.github.com"
# The helper is evaluated by git at call time; $GH_TOKEN must stay literal here.
# shellcheck disable=SC2016
git config --global credential.helper '!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'

# --- Clone & branch
mkdir -p "$(dirname "$WORKSPACE")"
git clone "https://github.com/$repo.git" "$WORKSPACE"
cd "$WORKSPACE"
git switch -c "$branch"
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
