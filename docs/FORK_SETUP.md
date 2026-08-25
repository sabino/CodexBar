---
summary: "Configure remotes and validate a checkout of sabino/CodexBar-Native."
read_when:
  - Cloning this fork
  - Configuring origin and upstream remotes
  - Recovering a local fork checkout
---

# Fork setup

Clone the fork and keep the original repository as a read-only upstream remote:

```bash
git clone git@github.com:sabino/CodexBar-Native.git
cd CodexBar-Native
git remote add upstream git@github.com:steipete/CodexBar.git
git fetch --all --tags --prune
git remote -v
```

The expected roles are:

- `origin`: `sabino/CodexBar-Native`, the only normal push and release target.
- `upstream`: `steipete/CodexBar`, fetched for compatibility and sync work.

Never push fork branches, cross-platform tags, release artifacts, appcast changes, or Homebrew changes to `upstream`.

## Toolchain check

```bash
swift --version
swift package resolve
swift build --traits CrossPlatformApp --product CodexBarCross
make check
make test
```

The shared renderer requires Swift 6.3.3 or newer on Linux/Windows, or Xcode 26's Swift toolchain on macOS. Platform
prerequisites are listed in [Cross-platform desktop app](CROSS_PLATFORM.md).

## First local sync

Create sync work from a fork branch, fetch the original repository, merge or rebase deliberately, then run the full
gates on the combined tree:

```bash
git switch -c feat/cross-platform-swift
git fetch upstream
git merge upstream/main
make check
make test
```

Resolve shared-core conflicts in favor of preserving upstream provider semantics plus the smallest portable adapter.
Regenerate checked-in hashes or manifests with their repository scripts instead of hand-editing generated values.
