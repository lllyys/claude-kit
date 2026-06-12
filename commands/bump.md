---
description: Bump the project version in its manifest, commit, tag, and push
argument-hint: "[patch | minor | major]"
---

# Bump Version

Bump the project's version following `.claude/rules/40-version-bump.md`:
the project's single source-of-truth version file is authoritative,
validated as semver, committed with a conventional message, tagged
`v<version>`, and pushed.

## Input

```text
$ARGUMENTS
```

Parse `$ARGUMENTS` for the semver level. Default to `patch` if empty.

| Input | Level |
|-------|-------|
| `patch` (or empty) | bug fixes — bump PATCH |
| `minor` | backwards-compatible features — bump MINOR |
| `major` | breaking changes — bump MAJOR |

If the argument is anything else: report the valid levels and STOP.

## Step 0: Identify the version source

Determine the project's single source-of-truth version file. Depending on
the stack this may be the `version` field in a manifest (`package.json`,
`pyproject.toml`), the `[package] version` in `Cargo.toml`, a `VERSION`
file, a build-system field, etc. Pick the one the project treats as
authoritative (rule 40 §1). Do not mirror the version into a second file
unless the stack strictly requires it.

## Step 1: Verify clean working tree

```bash
git status --porcelain
```

If the output is non-empty: report "Working tree is not clean — commit or
stash changes before bumping" and STOP. Never bump on top of unrelated
edits.

## Step 2: Read current version

Read the current version from the project's source-of-truth version file
(identified in Step 0). This is the only version to read or update.

## Step 3: Compute and write the new version

Bump the version file per the requested level **without** creating its own
commit or tag (we do those explicitly below). Use whatever the stack
provides (e.g. a manifest-aware bump command) or edit the version field
directly.

Confirm the result is valid semver (`MAJOR.MINOR.PATCH`) and capture it
into `NEW_VERSION`. If the version is not valid semver: revert the change
and STOP.

## Step 4: Commit

Commit the bump alone with a conventional message:

```bash
git add <version-file>
git commit -m "chore(release): bump version to ${NEW_VERSION}"
```

## Step 5: Tag

Create an annotated tag `v<version>`:

```bash
git tag -a "v${NEW_VERSION}" -m "v${NEW_VERSION}"
```

If the tag already exists: report the collision and STOP (do not overwrite).

## Step 6: Push

Push the commit and tag together:

```bash
git push --follow-tags
```

## Summary

Report:
- Old version → new version
- Bump level applied
- Commit SHA and tag name
- Confirmation the tag was pushed

## Safety Rules

1. **Single source of truth** — bump only the project's authoritative
   version file. Never mirror the version into a second file unless the
   stack strictly requires it (rule 40 §1).
2. **Clean tree required** — refuse to bump with uncommitted changes.
3. **Valid semver** — abort if the computed version is malformed.
4. **One commit** — the bump stands alone; no unrelated changes.
5. **Never overwrite a tag** — abort if `v<version>` already exists.
6. **Push with `--follow-tags`** — commit and tag travel together.
