# mcdiff

Small native macOS proof of concept for comparing two text files, choosing the left or right side for each changed block, and saving the merged result.

## Build

Requires `libgit2` from Homebrew:

```bash
brew install libgit2
make build
```

## Terminal launcher

After building, put the scripts directory on your PATH once:

```bash
export PATH="$PWD/Scripts:$PATH"
mcdiff old.txt new.txt
```

The command name is controlled by the launcher script's `COMMAND_NAME`
variable, so it can be renamed without digging through the script body.

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
