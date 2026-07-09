# Merged Caret Horizontal Scroll Debug Notes

Date: 2026-07-09

Log run inspected:

```text
/Users/golan.shabi/Library/Logs/mcdiff/2026-07-09:21:47:04_86290/
```

Files inspected:

```text
swift.log: 10 lines
cpp.log: 4 lines
```

## Issue

When editing a line wider than the visible merged pane, moving or typing past the visible horizontal boundary leaves the pane at the old horizontal offset. The caret can move out of view, which feels unlike a normal text editor.

## Relevant Logs

```text
2026-07-09 21:47:10 [INFO] ... PERF render total=18.7ms blocks=3 rows=47 preserving=false ...
2026-07-09 21:47:10 [INFO] ... PERF loadGitConflictFile total=36.6ms path=src/estore/defs/network_lock_pool.cpp ...
2026-07-09 21:47:11 [INFO] ... PERF input.textViewMouseDown elapsed_ms=87.0 ... pane=mergedSide ... editable=true
```

## Findings

The latest run shows interaction in the editable merged pane, but the existing logs do not record any automatic horizontal scroll request after selection movement.

The UI does not use a normal per-pane horizontal `NSScrollView` for the text content. It uses `PaneTextClipView.textOffset` plus shared `PaneHorizontalSlider` state, so AppKit's default caret auto-scroll is not enough to move the displayed panel horizontally.

## Hypotheses

The caret leaves the visible area because selection changes and edits update the `NSTextView` selection, but no code converts the selection location into the app's shared horizontal offset. This should be fixed by asking the owning `PaneTextClipView` to reveal the selection after real user input and merged text edits.

## Changes

Added horizontal selection reveal logic to `PaneTextClipView`, wired it through `PaneTextClipViewDelegate`, and applied the requested offset through the existing shared horizontal scroll state.

Called the reveal path after key input, mouse input, and merged text changes so typing and cursor movement keep the caret visible without resetting offsets during render-only selection restoration.

Added a regression assertion that a wide merged edit enables and advances the horizontal scroller.

## Verification

```text
make test
make build
```

Both commands passed.

## Next Steps

None for this issue.
