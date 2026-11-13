# mint-github-app-token OWNER/REPO
#
# Prints a GitHub App installation token that is valid for 1 hour and can
# only touch the one repository given. Nothing long-lived ever leaves the host:
# the App private key signs a 9-minute JWT here, and only the resulting token
# is handed to the VM.
#
# Environment: GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_KEY_FILE

repo=${1:?usage: mint-github-app-token OWNER/REPO}
repo_name=${repo#*/}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# 1. JWT proving "I am the App" (RS256, backdated 60s for clock skew)
now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
  "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID" | b64url)
signature=$(printf '%s.%s' "$header" "$payload" |
  openssl dgst -sha256 -sign "$GITHUB_APP_KEY_FILE" | b64url)
jwt="$header.$payload.$signature"

# 2. Exchange it for an installation token narrowed to one repo + 3 permissions
body=$(jq -n --arg r "$repo_name" '{
  repositories: [$r],
  permissions: {contents: "write", pull_requests: "write", issues: "write"}
}')

curl -fsS -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" \
  -d "$body" | jq -er '.token'
