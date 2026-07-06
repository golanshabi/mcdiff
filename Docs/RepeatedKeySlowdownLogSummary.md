# Repeated Key Slowdown Log Summary

Date: 2026-07-02

Run folder inspected:

```text
~/Library/Logs/mcdiff/2026-07-02:16:52:46_4917/
```

## Summary

The latest run shows the slowdown is caused by repeated full renders after text edits in the merged pane. The new edit instrumentation shows the app received repeated newline insertions, not space insertions:

```text
replacementKind=newline
renderReason=row_count
```

Every edit targeted the same merged block:

```text
blockIndexes=5
ranges=5@7211:<length>:editable=true:source=nil
```

The edited block started with 1 rendered row and grew to 30 rendered rows. Each newline increased the block row count by one, so the current edit path correctly chose a full render every time:

```text
beforeRows=1 afterRows=2
beforeRows=2 afterRows=3
...
beforeRows=29 afterRows=30
```

## Timings

There were 29 slow edit events.

```text
edit avg=108.8ms min=103.1ms max=114.2ms
replacementKind: newline=29
renderReason: row_count=29
```

Each edit was paired with a preserving render.

```text
render avg=105.4ms min=101.5ms max=108.9ms
rows 575 -> 603
```

Average render phase costs:

```text
contentWidths=29.4ms
clearViews=3.0ms
renderPlan=19.4ms
views=50.8ms
restoreSelection=2.8ms
```

The expensive work is rebuilding the UI views, plus measuring content widths and rebuilding the render plan.

## What This Means

The immediate cause is not Git or C++ work. The C++ log only shows repository discovery, conflict listing, and shutdown.

The edit path is slow because newline insertion changes row count. The current inline edit path only handles edits where row count stays stable. When row count changes, the app rebuilds the whole table, which costs about 100-110 ms per key repeat in this file.

The surprising finding is that the reproduction was logged as newlines. If the physical key pressed was Space, the next thing to verify is the raw key event entering the `NSTextView`, because the delegate saw `replacementString == "\n"` for every edit.

## Suggested Next Steps

1. Add temporary `keyDown` logging in `PaneTextView` for keyCode, modifier flags, and sanitized character kind before TextKit turns the event into an edit.
2. If the raw event is actually Space, investigate why it becomes newline before `shouldChangeTextIn`.
3. If the raw event is Return/Newline, optimize row-count-changing edits by updating only the merged text view and affected row metadata instead of full-rendering all panes.
4. Keep the current edit decision metadata until the next fix is verified, then remove or lower the noisy diagnostics.
