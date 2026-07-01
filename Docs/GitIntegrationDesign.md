# Git Integration Design

## Goal

Allow the user to run `mcdiff` from inside a git repository during a merge or
rebase conflict. The app should discover that repository, list the files that
need conflict resolution, open each conflicted file in the existing merge UI,
and save the resolved contents back to the worktree. In git mode, saving a
fully resolved file should also stage it with `git add`.

The program should also be configurable as the user's default git merge tool, so
`git mergetool` can invoke MacDiff directly for a single conflicted path.

The first version should focus only on conflict sections. Non-conflict additions
and removals can be highlighted in a later feature, but they should not block
the basic git conflict workflow.

## Current Shape

The command-line launcher currently requires exactly two file arguments:

```text
mcdiff <left-file> <right-file>
```

The app receives those two paths, reads both files, builds an `MDDocument`
through `MDMakeDiff`, renders the three-pane editor, and saves through an
`NSSavePanel`.

The merge editor already has the main model pieces needed for git conflict
resolution:

- `MDBlockKindEqual` for unchanged content.
- `MDBlockKindChanged` for a conflict/change block.
- `MDPickSideLeft`, `MDPickSideRight`, and `MDPickSideManual` for resolution.
- `MDDocument.mergedText()` for producing the resolved file text.

That means git mode can reuse the existing merge document and editor instead of
building a separate resolution surface.

## User Behavior

1. The user runs `mcdiff` from anywhere inside a git repository.
2. If the repository has unmerged paths, the app opens in git mode.
3. The app shows a list of conflicted files using repository-relative paths.
4. Selecting a file opens its conflict sections in the existing three-pane merge
   editor.
5. For each conflict block, the user can choose left, choose right, or manually
   edit the merged middle pane.
6. Save is enabled only when all conflict blocks in the selected file are
   resolved.
7. Saving in git mode writes the merged text to the conflicted worktree file and
   stages that path.
8. After a successful save and stage, the file is marked resolved in the list.
   The app can move to the next unresolved file.
9. When all files are resolved and staged, the app shows a simple completion
   state.

MacDiff should also support the standard git mergetool flow:

1. The user configures MacDiff as their default mergetool.
2. The user runs `git mergetool`.
3. Git invokes `mcdiff` for one conflicted file at a time.
4. MacDiff opens that file directly, writes the resolved result to Git's merged
   output path, and exits with a success status only after the file is resolved
   and saved.

Normal two-file compare should keep its existing behavior:

```text
mcdiff old.txt new.txt
```

In that mode, saving should continue to use `NSSavePanel`.

## Launcher Behavior

Update `Scripts/mcdiff` to accept zero arguments, two arguments, or a dedicated
mergetool invocation:

```text
mcdiff
mcdiff <left-file> <right-file>
mcdiff --merge-tool <base-file> <local-file> <remote-file> <merged-file>
```

For zero arguments, the launcher should pass the shell working directory to the
app because `open` does not give the app a reliable terminal cwd:

```text
open "$APP_BUNDLE" --args --git "$PWD"
```

For mergetool mode, the launcher should pass Git's paths through to the app and
wait for completion:

```text
"$APP_BUNDLE/Contents/MacOS/mcdiff" --merge-tool "$BASE" "$LOCAL" "$REMOTE" "$MERGED"
```

Running the app executable directly, or using an equivalent wrapper with an
explicit completion status, matters for `git mergetool`: Git needs the command
to return only after MacDiff has either saved the resolved file or cancelled,
and it needs the command's exit status to reflect that result. The app should
terminate with a successful exit status only after a resolved file has been
written to `$MERGED`.

The app should discover the repository root from that start path. If no git
repository is found, it should show a clear error such as:

```text
No git repository found for /path/from/terminal.
```

If the repository exists but has no unmerged paths, show:

```text
No conflicted files found.
```

## App Launch Modes

Introduce an explicit launch/session mode instead of inferring behavior from
optional URLs throughout `MainWindowController`.

Recommended Swift model:

```swift
private enum AppLaunchRequest {
    case empty
    case twoWayCompare(left: URL, right: URL)
    case git(startPath: URL)
    case gitMergeTool(base: URL, local: URL, remote: URL, merged: URL)
}

private enum SaveTarget {
    case savePanel
    case gitWorktreeFile(repositoryRoot: URL, relativePath: String)
    case mergeToolOutput(URL)
}
```

`MacDiffApp` should parse command-line arguments into `AppLaunchRequest`:

- no args: show the empty window, useful when launching the `.app` directly.
- two args: current two-file compare.
- `--git <path>`: git conflict workflow.
- `--merge-tool <base> <local> <remote> <merged>`: git mergetool workflow.

The launcher is the normal way to enter `--git` mode and `--merge-tool` mode.

## Default Git Mergetool Support

MacDiff should document and support a git configuration like:

```text
git config --global merge.tool mcdiff
git config --global mergetool.mcdiff.cmd 'mcdiff --merge-tool "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
git config --global mergetool.mcdiff.trustExitCode true
```

The exact install instructions can be refined when the launcher behavior is
implemented, but the program contract should be:

- `$BASE` is optional context for later diff3/non-conflict highlighting.
- `$LOCAL` is the left/ours side.
- `$REMOTE` is the right/theirs side.
- `$MERGED` is the worktree file path MacDiff must overwrite with the resolved
  result.
- MacDiff exits successfully only when `$MERGED` has been saved with every
  conflict resolved.
- MacDiff exits unsuccessfully if the user cancels, closes without saving, or a
  write fails.

The first mergetool implementation can build its document from `$MERGED` by
parsing conflict markers, the same as repo-session git mode. `$LOCAL`,
`$REMOTE`, and `$BASE` should still be accepted and retained in the session
model so later highlighting can compare against Git's side files without a
command-line compatibility break.

## Git Discovery

Use libgit2 for git-aware behavior where practical, since the project already
links libgit2 for diffing.

Bridge-level operations to add:

```objc
@interface MDGitConflictFile : NSObject
@property (copy) NSString *relativePath;
@property BOOL isTextConflict;
@property (copy) NSString *message;
@end

NSString *MDGitDiscoverRepository(NSString *startPath, NSError **error);
NSArray<MDGitConflictFile *> *MDGitConflictFiles(NSString *repositoryRoot, NSError **error);
BOOL MDGitStageFile(NSString *repositoryRoot, NSString *relativePath, NSError **error);
```

Implementation direction:

- Use `git_repository_discover` or `git_repository_open_ext` to find the repo
  root from the start path.
- Use the git index conflict iterator to list unmerged paths.
- Keep paths repository-relative for display, sorting, and staging.
- Stage resolved paths with `git_index_add_bypath` and `git_index_write`.

This avoids shelling out from the app and keeps git errors inside the existing
Objective-C bridge error pattern.

## Conflict Document Builder

The first git version should not diff the entire ours/theirs/base versions.
Instead, parse the conflicted worktree file and convert conflict markers into an
`MDDocument`.

Input example:

```text
before
<<<<<<< HEAD
ours
=======
theirs
>>>>>>> branch
after
```

Document output:

- Equal block: `before`
- Changed block:
  - left lines: `ours`
  - right lines: `theirs`
  - pick: `unpicked`
- Equal block: `after`

Add a bridge function:

```objc
MDDocument *MDMakeConflictDocument(NSString *worktreeText, NSError **error);
```

Recommended parser behavior:

- Treat lines outside conflict markers as equal blocks.
- Treat the text between `<<<<<<<` and `=======` as the left side.
- Treat the text between `=======` and `>>>>>>>` as the right side.
- Support diff3 markers by ignoring the optional base section between
  `|||||||` and `=======` for the first version.
- Preserve all non-conflict lines in the merged output through equal blocks.
- Return a recoverable error for malformed markers.
- Return an unsupported-file status for conflicted paths that are binary or
  cannot be read as UTF-8.

This matches the first milestone: only conflict sections become editable merge
blocks, and non-conflict additions/removals are carried through unchanged.

## Git Session UI

Keep the existing three-pane editor as the main workspace. Add git-session
chrome around it only when needed.

Recommended UI additions:

- A repository-relative conflicted file list.
- Per-file status: needs resolution, saved and staged, unsupported, or error.
- A `Save and Stage` button label in git mode.
- Optional `Previous` and `Next` controls for moving between conflicted files.

The file list can start as a simple left sidebar or compact top list. A sidebar
will scale better as soon as there are many conflicted files, but the first
implementation should stay modest and native.

When a file is selected:

1. Read the worktree file.
2. Build an `MDDocument` with `MDMakeConflictDocument`.
3. Render it with the current editor.
4. Set `SaveTarget.gitWorktreeFile(repositoryRoot:relativePath:)`.

## Save And Stage

Update save behavior to branch on `SaveTarget`.

For normal two-file compare:

1. Ask `document.mergedText()`.
2. Show `NSSavePanel`.
3. Write to the selected URL.

For git mode:

1. Require `document.canSave()`.
2. Ask `document.mergedText()`.
3. Write the text directly to the selected conflicted worktree path.
4. Stage the file with `MDGitStageFile`.
5. Mark the file resolved in the session list.
6. Refresh the repository conflict list or update the saved row locally.

The save operation should be all-or-visible:

- If writing fails, do not stage.
- If staging fails, keep the file marked unresolved and show the git error.
- If both succeed, the file row becomes resolved/staged.

For mergetool mode:

1. Require `document.canSave()`.
2. Ask `document.mergedText()`.
3. Write the text directly to the `$MERGED` path.
4. Record that the tool completed successfully.
5. Terminate the app with a success exit status so `git mergetool` can continue.

Mergetool mode should not run `git add` itself in the first version. Git owns
the surrounding `git mergetool` control flow, and `trustExitCode` should tell Git
whether MacDiff completed the file successfully.

## Future Non-Conflict Highlighting

After the basic conflict workflow works, add visual diff information for
non-conflict additions and removals.

That feature should be treated as decorations over the git conflict document,
not as extra unresolved blocks. Non-conflict hunks have already been accepted by
git's merge machinery, so they should not require a pick and should not block
save readiness.

Likely data sources:

- Index stage 1: base version.
- Index stage 2: ours.
- Index stage 3: theirs.
- Worktree file: conflict-marker file before resolution, resolved file after
  save.

Possible implementation path:

1. Load base/ours/theirs blobs for each conflicted path from the index.
2. Compute decorations for non-conflicting changes outside conflict marker
   ranges.
3. Add decoration runs to `RenderPlan` separately from `MDBlock.kind`.
4. Use subdued colors or gutters for non-conflict additions/removals so they do
   not look like unresolved conflict choices.

Do not mix this into the first conflict-only parser. Keeping decorations
separate will prevent future highlighting from changing merged output behavior.

## Edge Cases

The first git version should explicitly handle or report:

- No git repository found.
- Git repository found but no unmerged paths.
- Multiple conflicted files.
- Multiple conflict blocks in one file.
- Diff3 conflict markers.
- Malformed conflict markers.
- UTF-8 read failures.
- Binary conflicts.
- Modify/delete or rename/delete conflicts without standard worktree markers.

Unsupported conflict types can appear in the file list with a clear message and
can be skipped in the first implementation.

## Test Plan

Core tests:

- Parse one conflict marker block.
- Parse multiple conflict marker blocks.
- Preserve equal text before, between, and after conflicts.
- Ignore diff3 base sections.
- Reject malformed markers.
- Verify `mergedText()` removes markers and writes selected/manual content.

Bridge tests:

- `MDMakeConflictDocument` returns expected `MDBlock` objects.
- Parser errors become `NSError` values.

Git integration tests:

- Create a temporary repository with a text merge conflict.
- Verify git mode lists the conflicted file.
- Resolve the file through an `MDDocument`.
- Save and stage it.
- Verify the worktree file no longer contains conflict markers.
- Verify the index no longer reports the path as unmerged.

Swift UI tests:

- Git mode shows a conflicted file list.
- Selecting a file renders the conflict blocks.
- Save is disabled before resolution.
- Save and stage marks the file resolved.

Mergetool tests:

- Invoke the launcher/app argument parser with `--merge-tool` paths.
- Verify `$MERGED` conflict markers are parsed into an `MDDocument`.
- Resolve and save the document.
- Verify `$MERGED` contains the resolved text.
- Verify success is reported only after save.
- Verify cancelling or closing without save reports failure.

## Milestones

1. Add launch parsing and launcher support for `mcdiff` with no file args.
2. Add git repository discovery and unmerged-path listing.
3. Add conflict-marker parser and bridge function.
4. Add git session state and conflict file list UI.
5. Add git-mode save and stage behavior.
6. Add default git mergetool mode and document the git configuration.
7. Add focused tests for parser, git staging, mergetool exit behavior, and UI
   save readiness.
8. Later: add non-conflict addition/removal highlighting as decorations.
