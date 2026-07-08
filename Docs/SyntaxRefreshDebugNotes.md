# Syntax Refresh Debug Notes

Date: 2026-07-08

Log run inspected:

```text
/Users/golan.shabi/Library/Logs/mcdiff/2026-07-08:15:50:37_92841/
```

Files inspected:

```text
swift.log: 311 lines
cpp.log: 5 lines
```

## Issue

After syntax coloring was added, typing in the editable merged pane could make colors disappear and not visibly return after the intended idle refresh.

## Relevant Logs

The latest run contains merged-pane edits and a few syntax refresh entries:

```text
swift.log:25 - PERF input.refreshSyntaxHighlighting elapsed_ms=8.0 blocks=7 rows=143 gitMode=true previewMode=false pane=mergedSide length=4010 preserveSelection=true
swift.log:36 - PERF input.refreshSyntaxHighlighting elapsed_ms=16.1 blocks=7 rows=143 gitMode=true previewMode=false pane=mergedSide length=4014 preserveSelection=true
swift.log:88 - PERF input.refreshSyntaxHighlighting elapsed_ms=8.3 blocks=7 rows=143 gitMode=true previewMode=false pane=mergedSide length=4006 preserveSelection=true
```

The same run also shows many inline edit/undo restores around the editable merged pane:

```text
swift.log:30 - PERF restoreMergedSnapshotsInline total=19.1ms action=Edit route=inline reason=ok ... replaceText=11.9ms
swift.log:294 - PERF restoreMergedSnapshotsInline total=9.1ms action=Edit route=inline reason=ok ... replaceText=2.1ms
```

## Findings

The idle refresh timer did fire in the latest run, so the symptom was not simply "timer never runs."

The editable pane was still configured with `isRichText = false`. That is a risky configuration for visual syntax highlighting because typed edits can flatten text attributes in an editable `NSTextView`.

The previous refresh path replaced the attributed storage, but did not explicitly invalidate TextKit layout/display for the full text after reapplying syntax attributes.

The previous scheduling happened only after a successfully captured model edit. If AppKit sent a merged text change without `pendingMergedEdit`, no idle syntax refresh was scheduled.

## Changes

The editable text view now allows attributed text display while paste remains plain text through the existing paste override.

The syntax refresh now wraps storage replacement in `beginEditing`/`endEditing`, invalidates layout and display for the full character range, and forces the text view to display.

`textDidChange` now schedules the idle syntax refresh for every merged text change before checking whether a model edit was captured.

## Verification

Passed:

```text
make test
make build
```
