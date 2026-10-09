#!/usr/bin/env bash
# One-time GitHub-side setup for the native_auto_merge test target.
# Requires: gh CLI authenticated (`gh auth login`) with admin on the target owner/org.
set -euo pipefail

: "${GH_OWNER:?set GH_OWNER to your github user or org}"
: "${REPO_NAME:=changeflow-test-native-auto-merge}"
REVIEWER_LOGIN="${REVIEWER_LOGIN:-punitlad}"

echo "==> Repo: $GH_OWNER/$REPO_NAME"

if gh repo view "$GH_OWNER/$REPO_NAME" >/dev/null 2>&1; then
  echo "    already exists, pushing current content"
  git remote add origin "https://github.com/$GH_OWNER/$REPO_NAME.git" 2>/dev/null || true
  git push -u origin main
else
  echo "    creating + pushing"
  gh repo create "$GH_OWNER/$REPO_NAME" --public --source=. --remote=origin --push
fi

echo "==> Enabling 'Allow auto-merge'"
gh api -X PATCH "repos/$GH_OWNER/$REPO_NAME" -f allow_auto_merge=true >/dev/null

echo "==> Creating branch ruleset on main (PR + required 'validate' check, NO required review)"
gh api -X POST "repos/$GH_OWNER/$REPO_NAME/rulesets" --input - >/dev/null <<EOF
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "rules": [
    {"type": "pull_request"},
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [{"context": "validate"}],
        "strict_required_status_checks_policy": true
      }
    }
  ]
}
EOF

echo "==> Creating 'production' environment with $REVIEWER_LOGIN as required reviewer"
REVIEWER_ID=$(gh api "users/$REVIEWER_LOGIN" --jq .id)
gh api -X PUT "repos/$GH_OWNER/$REPO_NAME/environments/production" --input - >/dev/null <<EOF
{
  "reviewers": [{"type": "User", "id": $REVIEWER_ID}],
  "deployment_branch_policy": null
}
EOF

cat <<MSG

Done. Remaining manual step:
  Install the GitHub App on this repo:
  https://github.com/settings/apps/my-changeflow-app -> Install App -> $GH_OWNER/$REPO_NAME

Then point changeflow at it (see README.md "Run changeflow against it").
MSG
