# 40 - Version Bump

Every release bumps **one** source-of-truth version. Where that version
lives depends on the project's stack — the `version` field in
`package.json`, the `[package] version` in `Cargo.toml`, the `version` in
`pyproject.toml`, a `VERSION` file, a build-system field, etc. Identify your
project's single version source and bump only it; if the stack genuinely
requires mirroring (e.g. a desktop app config that must match), keep that to
the minimum the stack demands and document it.

## Rules

1. **Single source of truth.** Bump the version in your project's
   manifest/version file (`package.json`, `Cargo.toml`, `pyproject.toml`,
   `VERSION`, etc.) — pick the one your stack treats as authoritative. Do
   not mirror the version into a second file unless the stack strictly
   requires it.
2. **Semver.** The new version must be valid [semver](https://semver.org/)
   (`MAJOR.MINOR.PATCH`). Choose the level by change type:
   - `patch` — bug fixes, no API/behavior change
   - `minor` — backwards-compatible features
   - `major` — breaking changes
3. **Clean tree first.** Refuse to bump unless `git status --porcelain` is
   empty. Stash or commit unrelated work before bumping.
4. **Conventional commit.** Commit the bump alone with a conventional
   message: `chore(release): bump version to X.Y.Z`.
5. **Tag.** Tag the bump commit `v<version>` (e.g. `v1.4.0`). One annotated
   tag per release.
6. **Push.** Push the commit and the tag together with
   `git push --follow-tags`.

## Sequencing

- In the feature workflow (`.claude/rules/47-feature-workflow.md`) the
  version bump is the **last commit before opening the PR** for each Work
  Item.
- In the fix-issue flow the bump is the mandatory tail commit before the
  PR (`patch` level for pure bug fixes).
- When multiple branches land in sequence, assign distinct, non-colliding
  versions in merge order so two PRs never claim the same `vX.Y.Z`.

## Anti-patterns

- Inventing a parallel version bump across multiple files when the stack
  has a single authoritative version source.
- Bumping with a dirty working tree.
- Tagging without pushing the tag (`git push` without `--follow-tags`).
- Mixing the version bump with unrelated changes in one commit.
