# mcdiff

Small native macOS proof of concept for comparing two text files, choosing the left or right side for each changed block, and saving the merged result.

## Build

Requires `libgit2` from Homebrew:

```bash
brew install libgit2
make build
```

For a build with Swift and C++ logging compiled out:

```bash
make build LOGGING=0
```

## Terminal launcher

After building, put the scripts directory on your PATH once:

```bash
export PATH="$PWD/Scripts:$PATH"
mcdiff old.txt new.txt
```

The command name is controlled by the launcher script's `COMMAND_NAME`
variable, so it can be renamed without digging through the script body.

Run `mcdiff` with no file arguments from inside a git repository to open the
current changed files. Ordinary changes are shown as read-only `HEAD` to
worktree diffs, and conflicted files keep the resolve-and-stage workflow:

```bash
mcdiff
```

To use MacDiff as the default git mergetool:

```bash
git config --global merge.tool mcdiff
git config --global mergetool.mcdiff.cmd 'mcdiff --merge-tool "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
git config --global mergetool.mcdiff.trustExitCode true
```

## Tests

```bash
make test
```

## Logs

Each run creates a dedicated log folder named `<Date>:<TIME>_<PID>`. Swift
and C++ write separate logs inside that run folder:

```text
~/Library/Logs/mcdiff/<Date>:<TIME>_<PID>/swift.log
~/Library/Logs/mcdiff/<Date>:<TIME>_<PID>/cpp.log
```

If that directory is not writable, the app falls back to the system temp
directory. Only the 10 most recent run folders are kept.
