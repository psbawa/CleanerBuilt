# Cleaner Built

A native macOS app that safely finds and removes files you don't need: caches, logs, temp files, Xcode leftovers, developer and browser caches. **Safety matters more than space freed.**

Swift 6 · SwiftUI · macOS 14+ · no third-party dependencies.

## Safety rules

- **Moves to the Trash, never deletes.** Everything goes through `FileManager.trashItem`, so you can put it back. The only permanent action is **Empty Trash**, which asks you to confirm first.
- **Preview first.** Every clean starts with a dry-run scan. You choose what to remove before anything moves.
- **Allowlist only.** The app can only touch paths listed in [`CleanupRules.swift`](CleanerBuilt/CleanupRules.swift).
- **Hard denylist.** System folders, Keychains, iCloud Drive, Mail, Messages, Photos, Documents, Desktop, Pictures, Music, Movies and app data are always off-limits, even if a rule would include them.
- **No symlinks followed.** Every path is resolved and re-checked against the allowed folders.
- **Skips anything in use.** Open files, caches of running apps, iCloud placeholder files, and anything used in the last 7 days (you can change this).
- **No admin rights.** No sudo, no privileged helper. It works on your user files only.
- **Checks again before trashing.** Every item is re-checked right before it moves.
- **Everything is logged** to `~/Library/Logs/CleanerBuilt/actions.jsonl` and shown in History.

## What it cleans

| Category | Where |
|---|---|
| App Caches | `~/Library/Caches` (Apple's own caches excluded) |
| App Logs | `~/Library/Logs` |
| Temporary Files | `$TMPDIR` |
| Xcode | DerivedData, Archives (opt-in), DeviceSupport (keeps the newest 2), unavailable simulators (opt-in) |
| Developer Caches | npm, Yarn, pip, CocoaPods, Gradle, Homebrew (opt-in) |
| Browser Caches | Safari, Chrome, Firefox (cache only, never history or passwords) |
| Large Files | `~/Downloads` files over 500 MB not opened in 90+ days. Review only, never removed automatically. |

`brew cleanup` and `simctl delete unavailable` run through their own tools and **can't be undone**. They're off by default and marked as permanent.

## Build and run

1. Open `Cleaner Built.xcodeproj` in Xcode.
2. Choose the **Cleaner Built** scheme and press ⌘R. Press ⌘U to run the tests.
3. Grant **Full Disk Access** when the app asks: System Settings › Privacy & Security › Full Disk Access.

To build it yourself, change the signing team in the target settings to your own. The app runs outside the App Sandbox, with Hardened Runtime on, and is meant for Developer ID distribution.

## Tests

55 tests (Swift Testing) cover the path guard, scanner and cleaner. They run in a temporary folder and never touch your real files.
