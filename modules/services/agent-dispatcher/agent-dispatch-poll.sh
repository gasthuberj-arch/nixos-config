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
    agent-dispatch-once --repo "$repo" --issue "$issue" || true
  done
done
