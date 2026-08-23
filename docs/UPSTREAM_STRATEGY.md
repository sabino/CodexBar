---
summary: "Keep sabino/CodexBar synchronized with steipete/CodexBar without contaminating upstream releases."
read_when:
  - Syncing this fork with upstream
  - Resolving shared-core conflicts
  - Preparing a potentially upstreamable change
---

# Upstream strategy

## Remote roles

```bash
git remote -v
# origin   git@github.com:sabino/CodexBar.git
# upstream git@github.com:steipete/CodexBar.git
```

Fetch from both remotes, push only to `origin`, and never repoint release scripts at upstream as part of normal fork
work.

## Synchronizing

```bash
git status --short
git fetch upstream --tags
git log --oneline --left-right HEAD...upstream/main
git merge upstream/main
```

Before syncing, preserve unrelated local work and start from a clean, reviewable fork branch. After conflict
resolution, regenerate checked-in provider manifests, parser hashes, plugin JavaScript, and docs indexes with their
own scripts, then run `make check` and `make test`.

## Conflict policy

- Preserve upstream provider and parser semantics in `CodexBarCore`.
- Preserve portable behavior by adapting the shared model at the narrowest boundary in `CodexBarCross` or
  `CodexBarCrossSupport`.
- Do not duplicate provider implementations merely to avoid a merge conflict.
- Keep macOS-only capabilities in the original app unless a real portable source exists.
- Keep provider identity and account data siloed.

## Contribution-ready changes

Potentially upstreamable work should be small, tested, free of fork release metadata, and useful independently of
`sabino/CodexBar`. Create an upstream PR branch from `upstream/main`, cherry-pick only the relevant commits, and review
the complete diff against upstream. Do not include fork tags, GitHub release workflow policy, ad-hoc bundle identity,
or fork documentation.

Preparing a clean branch does not authorize opening a pull request. A PR to `steipete/CodexBar` must be explicitly
requested as a separate action.
