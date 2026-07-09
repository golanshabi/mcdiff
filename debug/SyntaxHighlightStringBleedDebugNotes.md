# Syntax Highlight String Bleed Debug Notes

Date: 2026-07-09

Log run inspected:

```text
/Users/golan.shabi/Library/Logs/mcdiff/2026-07-09:14:33:11_1835/
```

Files inspected:

```text
swift.log: 308 lines
cpp.log: 4 lines
```

## Issue

In Git conflict mode, `src/estore/estore_migrate.cpp` shows large regions of
ordinary C++ code colored red. The screenshot shows the coloring starts around a
macro argument that includes a quote and then bleeds into later code.

## Relevant Logs

```text
swift.log:6
2026-07-09 14:33:11 [INFO] MainWindowController_Git.swift:loadGit(startPath:):69 - Received git session start_path=/Users/golan.shabi/git/orion

swift.log:14
2026-07-09 14:33:21 [INFO] MainWindowController_Utilities.swift:logPerformance(_:phases:metadata:minimumTotalMilliseconds:):85 - PERF loadGitConflictFile total=65.8ms path=src/estore/estore_migrate.cpp updateGitControls=16.5ms readFile=1.4ms parseConflict=15.8ms render=32.1ms

swift.log:84
2026-07-09 14:33:57 [INFO] MainWindowController_Utilities.swift:logInputPerformance(_:milliseconds:metadata:):96 - PERF input.refreshSyntaxHighlighting elapsed_ms=19.4 blocks=7 rows=867 gitMode=true previewMode=false pane=mergedSide length=47145 preserveSelection=true
```

## Findings

- The affected pane is using `SyntaxHighlighter` for a C++ file.
- The shared string regex is:

```text
"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'
```

- In that regex, `[^"\\]` and `[^'\\]` can match newline characters. If a line
  contains an unmatched quote, or a macro/string-like expression is split across
  lines while a matching quote appears later, the string match can span many
  lines and recolor ordinary code as `.systemRed`.

## Interpretation

The red flood is a syntax-highlighting bug, not a diff-rendering or conflict
state bug. For C-like, Swift, Python, shell, JSON, YAML, HTML, and CSS highlighting,
normal single-line string matching should stop at line boundaries.

## Changes

- Restricted the shared string regex so quoted strings do not match across
  newlines:

```text
"(?:\\.|[^"\\\n\r])*"|'(?:\\.|[^'\\\n\r])*'
```

- Applied the same line-boundary restriction to JSON object-key highlighting.
- Added a regression assertion that a C++ unterminated string on one line does
  not color `plain_identifier` on the following line as `.systemRed`.

## Verification

```text
make test
make build
```

Both passed on 2026-07-09.
