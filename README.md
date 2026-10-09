# changeflow test target: `native_auto_merge`

Validates `CHANGEFLOW_MERGE_MODE=native_auto_merge` — changeflow enables GitHub's built-in
auto-merge via `enablePullRequestAutoMerge`, and GitHub merges the PR itself once the
required status check passes. **Validated end-to-end.**

## What's here

| File | Purpose |
|---|---|
| `teams.json` | The file changeflow appends `{"team": "<name>"}` to |
| `.github/workflows/ci.yml` | PR-time check (`validate`) — the ruleset's required status check |
| `.github/workflows/deploy.yml` | The pipeline triggered by the merge, gated by the `production` environment |
| `setup.sh` | One-time `gh` CLI setup for this repo (ruleset, auto-merge toggle, environment) |

## Why this mode specifically needs this layout

- **"Allow auto-merge" must be ON** for the repo, or `enablePullRequestAutoMerge` has nothing
  to attach to.
- **A branch ruleset with at least one requirement** must exist on `main`, otherwise GitHub
  merges immediately on PR open (harmless, but doesn't actually exercise auto-merge waiting
  on a check — the point of this test target).
- **No required review.** A GitHub App cannot approve its own PR, so if the ruleset requires
  an approving review, auto-merge will stall forever. This is the mode's main caveat from the
  main README — `setup.sh` intentionally only adds a required status check, not a review
  requirement.

## One-time setup

```bash
export GH_OWNER=<your-github-user-or-org>
export REPO_NAME=changeflow-test-native-auto-merge   # or whatever you name it
./setup.sh
```

`setup.sh` will:
1. `gh repo create` (if `REPO_NAME` doesn't exist yet) and push this directory to it
2. Turn on "Allow auto-merge" (`PATCH /repos/{owner}/{repo}` `allow_auto_merge=true`)
3. Create a branch ruleset on `main`: require a pull request + the `validate` status check,
   no required reviewers
4. Create the `production` environment with `punitlad` as a required reviewer (for the
   approval step — `CHANGEFLOW_APPROVAL_MODE=pending_deployments`)

Then **install your GitHub App on this repo** (Settings → GitHub Apps → your App → configure
→ add this repo) — `setup.sh` can't do that part, it's an App-installation action on
`https://github.com/settings/apps/my-changeflow-app`.

## Run changeflow against it

```bash
export CHANGEFLOW_TARGET_OWNER=$GH_OWNER
export CHANGEFLOW_TARGET_REPO=$REPO_NAME
export CHANGEFLOW_MERGE_MODE=native_auto_merge
export CHANGEFLOW_MERGE_METHOD=squash
export CHANGEFLOW_APPROVAL_MODE=pending_deployments
export CHANGEFLOW_PIPELINE_ENVIRONMENT=production
export CHANGEFLOW_APPROVER_TOKEN=<a PAT for punitlad with repo + workflow scope>
# ...plus CHANGEFLOW_APP_ID / CHANGEFLOW_APP_PRIVATE_KEY / CHANGEFLOW_INSTALLATION_ID
uvicorn changeflow.api:app
curl -XPOST localhost:8000/team-onboardings -d '{"team":"payments","requested_by":"you"}'
```

## What "validated" looks like

`GET /team-onboardings/{id}` reaches `phase: succeeded`, having passed through `pr_open` →
`merging` → `merged` → `pipeline_running` without changeflow ever touching the merge button —
GitHub did it once `validate` went green. In testing, `merging` → `merged` took ~30-40s (the
wait on `validate`) — noticeably slower than `ruleset_bypass`'s near-instant merge.

## Trade-offs for team discussion

- **Moderate trust grant** — no bypass list entry, no elevated REST merge rights; the App
  only ever asks GitHub to auto-merge once checks pass, same mechanism any human's PR with
  auto-merge enabled would use.
- **Can't require a review alongside it.** A GitHub App can't approve its own PR, so if their
  branch ruleset requires an approving review (common for anything touching production config),
  this mode simply never merges — it waits forever. Worth asking upfront whether the target
  repo's ruleset already requires reviews.
- **Slower than `ruleset_bypass`** by however long their required checks take to run — fine
  for a fast CI job, a real concern if their checks are slow or flaky.
- **Easiest to explain to a target team**, since nothing about trust changes: "allow our App's
  PR to auto-merge like anyone else's, once your own checks pass" is a one-line ask with no new
  bypass concept to approve.
