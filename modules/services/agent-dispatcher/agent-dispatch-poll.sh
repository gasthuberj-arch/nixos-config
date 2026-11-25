# agent-dispatch-poll: run one job per open issue carrying TRIGGER_LABEL.
# Environment: REPOSITORIES (space separated OWNER/REPO), TRIGGER_LABEL

for repo in $REPOSITORIES; do
  GH_TOKEN=$(mint-github-app-token "$repo") || {
    echo "agent-dispatch-poll: cannot mint token for $repo" >&2
    continue
  }
  issues=$(GH_TOKEN=$GH_TOKEN gh issue list --repo "$repo" --state open \
    --label "$TRIGGER_LABEL" --json number --jq '.[].number')
  for issue in $issues; do
    rc=0
    agent-dispatch-once --repo "$repo" --issue "$issue" || rc=$?
    # 75: every orb slot is busy (e.g. interactive orbs); the issue keeps
    # its label, so the next timer tick picks it up.
    if ((rc == 75)); then
      echo "agent-dispatch-poll: no free orb slot; retrying next tick"
      exit 0
    fi
  done
done
