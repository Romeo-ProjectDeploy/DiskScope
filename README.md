# DiskScope

A native, local-only macOS storage analyzer built with SwiftUI. macOS 14+; no server, account, Docker, or external packages required.

## First version

- Choose a folder or scan Applications, Home, or Downloads.
- Ranked files and aggregated .app bundles, allocated disk usage, top-folder bars, search, and app filter.
- Reveal files in Finder.
- Inaccessible paths are reported as a partial scan. Cloud placeholders and symbolic links are skipped; hard links are counted once. Trash is excluded.
- Select items, review full paths, acknowledge the review, then move eligible items to Finder's Trash. No permanent deletion or automatic emptying.
- System locations, hidden configuration, and user Library data are review-only. Manage those through the owning app.

## Run

Install Apple's Command Line Tools (`xcode-select --install`) if needed, then:

```sh
./scripts/build-app.sh
open dist/DiskScope.app
```

Optional tests:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/diskscope-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/diskscope-module-cache swift run --disable-sandbox --cache-path /tmp/diskscope-cache DiskScopeChecks
```

The locally built application uses ad-hoc signing and is not notarized for distribution. A public release needs Developer ID signing and notarization.

## Permissions and limits

Use Choose folder for explicit access. macOS can deny protected folders; the app reports those areas rather than bypassing access checks. Full Disk Access can be granted in System Settings > Privacy & Security if desired, but is not required for ordinary folder scans. Rescan after changing permissions.

Displayed sizes measure allocated file bytes, not guaranteed recoverable space. APFS clones, snapshots, compression, hard links, excluded directories, and unreadable files mean scan totals will not match all volume usage. Totals remain a snapshot until Rescan. App bundle sizes exclude separate app data. Deleting a cloud-synced local file may also delete the synced copy. Files in active use should be managed through their application. Restore trashed items using Finder's Trash > Put Back.

No phone access is included in version 0.1. No files or scan results leave the Mac.
