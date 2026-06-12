---
description: Remove failed/canceled GitHub Actions runs and stale remote branches
---

# Repository Cleanup

Clean up the remote repository by removing failed CI artifacts and stale branches.

## Step 1: Delete Failed GitHub Actions Runs

```bash
gh run list --status failure --limit 100 --json databaseId --jq '.[].databaseId'
```

Delete each run with `gh run delete <id>`.

Report: `Deleted N failed runs.`

## Step 2: Delete Canceled GitHub Actions Runs

```bash
gh run list --status cancelled --limit 100 --json databaseId --jq '.[].databaseId'
```

Delete each run with `gh run delete <id>`.

Report: `Deleted N canceled runs.`

## Step 3: Delete Stale Remote Branches

List all remote branches except `main`:

```bash
git fetch --prune
gh api repos/{owner}/{repo}/branches --paginate --jq '.[].name' | grep -v '^main$'
```

Delete each branch with `gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/{branch}`.

Report: `Deleted N remote branches.`

## Step 4: Prune Local Tracking References

```bash
git fetch --prune
```

## Summary

Report total cleanup: `Cleanup complete: N failed runs, N canceled runs, N branches removed.`
