# Git Conflict Without Markers Debug Notes

Date: 2026-07-09

Log run inspected:

```text
/Users/golan.shabi/Library/Logs/mcdiff/2026-07-09:10:45:21_51655/
```

Files inspected:

```text
swift.log: 72 lines
cpp.log: 4 lines
```

## Issue

Selecting `src/estore/gn/write_lease/gn_write_lease_generation.cpp` from the Git-mode
`Needs Resolution` list shows:

```text
No conflict markers found in /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp.
```

## Relevant Logs

```text
swift.log:6
2026-07-09 10:45:21 [INFO] MainWindowController_Git.swift:loadGit(startPath:):69 - Received git session start_path=/Users/golan.shabi/git/orion

cpp.log:2-4
2026-07-09 10:45:21 [INFO] GitRepository.cpp:discoverGitRepository:139 - Discovered git repository root=/Users/golan.shabi/git/orion/
2026-07-09 10:45:21 [INFO] GitRepository.cpp:gitConflictFiles:180 - Listed git conflict files count=46
2026-07-09 10:45:23 [INFO] GitRepository.cpp:gitChangedFiles:231 - Listed git changed files count=2936

swift.log:65-66
2026-07-09 14:13:26 [ERROR] MainWindowController_Git.swift:loadGitConflictFile(at:):207 - Git conflict load failed: No conflict markers found in /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp.
2026-07-09 14:13:26 [ERROR] MainWindowController_Utilities.swift:show(_:):47 - Showing alert: No conflict markers found in /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp.
```

## Findings

- McDiff puts the file under `Needs Resolution` because libgit2 returns it from
  `git_index_conflict_iterator`.
- `loadGitConflictFile` treats every `isConflict && isTextConflict` entry as a
  marker-based text conflict and calls `loadConflictDocument`.
- `loadConflictDocument` throws this specific alert when `MDMakeConflictDocument`
  parses successfully but produces no changed blocks.
- The worktree file has no conflict marker lines matching `<<<<<<<`, `=======`,
  `>>>>>>>`, or diff3 `|||||||`.
- Git still reports the file as unmerged:

```text
git status --porcelain=v1 --untracked-files=no -- src/estore/gn/write_lease/gn_write_lease_generation.cpp
UD src/estore/gn/write_lease/gn_write_lease_generation.cpp
```

- The index has stages 1 and 2 only:

```text
100644 a69ee38a64431aab4be32ebce8cf4eb22faf1140 1	src/estore/gn/write_lease/gn_write_lease_generation.cpp
100644 8d54a01c8076dc688b76f9c5672e474bb987e9ff 2	src/estore/gn/write_lease/gn_write_lease_generation.cpp
```

## Interpretation

This is a Git delete/modify conflict, not a normal both-modified text conflict.
The worktree contains the local/ours version of the file, while the other side
deleted it. Git therefore has an unresolved conflict entry, but the file does not
contain inline conflict markers for McDiff to parse.

## Changes

- Added a markerless-unmerged handling path in Git mode.
- When a Git conflict parses to no marker blocks, McDiff now shows:

```text
file has no conflicts but is unmerged
```

- The alert offers `Add to Git`. Choosing it calls the existing staging bridge,
  marks the path resolved in the current UI session, and moves it from
  `Needs Resolution` to `Review Changes`.
- Added a regression fixture for a delete/modify conflict with no inline markers.

## Verification

Commands run:

```text
rg -n "^<<<<<<<|^=======|^>>>>>>>|^\\|\\|\\|\\|\\|\\|\\|" /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp
sed -n '1,120p' /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp
wc -l /Users/golan.shabi/git/orion/src/estore/gn/write_lease/gn_write_lease_generation.cpp
git -C /Users/golan.shabi/git/orion ls-files -u -- src/estore/gn/write_lease/gn_write_lease_generation.cpp
git -C /Users/golan.shabi/git/orion status --porcelain=v1 --untracked-files=no -- src/estore/gn/write_lease/gn_write_lease_generation.cpp
```

Observed:

```text
marker search: no matches
worktree file length: 55 lines
status: UD src/estore/gn/write_lease/gn_write_lease_generation.cpp
```

Follow-up verification after the UI change:

```text
make test
make build
```

Both commands passed on 2026-07-09.

## Next Steps

McDiff now supports the "keep/add the worktree file" path for markerless
unmerged files. A future improvement could expose the opposite delete-side
resolution explicitly for delete/modify conflicts.
