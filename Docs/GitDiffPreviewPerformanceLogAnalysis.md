# Git Diff Preview Performance Log Analysis

Date: 2026-07-07

Run folder inspected:

```text
~/Library/Logs/mcdiff/2026-07-07:13:03:08_57134/
```

Files inspected:

```text
swift.log: 23 lines
cpp.log: 11 lines
```

## Summary

The latest run shows two separate costs.

First, Git activation is slow because the new all-diff mode enumerates a very large change set. The run listed 2,937 changed files and spent almost all of the Git activation time inside change listing:

```text
swift.log:7 - PERF loadGit total=2395.8ms files=2937 discoverRepo=6.6ms listChanges=2389.1ms
cpp.log:4 - Listed git changed files count=2937
```

Second, the interactive slowdown after opening the file is dominated by the Swift/AppKit rendering and text interaction path, not by C++ diff construction. Loading `.gitlab-ci.yml` took 4,152.9 ms, and 3,810.9 ms of that was render time:

```text
swift.log:10 - PERF loadGitDiffFile total=4152.9ms path=.gitlab-ci.yml status=staged modified updateGitControls=237.9ms readHead=10.6ms readWorktree=1.2ms diff=92.3ms render=3810.9ms
```

The render itself was for a very large document: 253 blocks and 35,159 rows. Most of the render time was spent creating/updating views and measuring content widths:

```text
swift.log:9 - PERF render total=3809.1ms blocks=253 rows=35159 preserving=false contentWidths=922.7ms clearViews=0.0ms renderPlan=47.8ms views=2838.6ms refreshWidths=0.0ms restoreSelection=0.0ms
```

Phase breakdown:

```text
views=2838.6ms, 74.5% of render
contentWidths=922.7ms, 24.2% of render
renderPlan=47.8ms, 1.3% of render
```

## C++ / Bridge Evidence

The C++ side saw a large diff request, but the measured Swift phases say the diff work itself was not the main cost. The input files were around 1 MB each:

```text
cpp.log:5 - Bridge requested diff left_chars=985256 right_chars=999378
cpp.log:7 - Building diff left_bytes=990137 right_bytes=1004259
cpp.log:8 - Built diff blocks=253
cpp.log:9 - Bridge produced document blocks=253
```

Swift measured the actual diff phase at only 92.3 ms:

```text
swift.log:10 - diff=92.3ms render=3810.9ms
```

There are no C++ log entries during the later slow cursor placement events at `13:03:20` through `13:03:33`. That points away from the bridge or C++ diff engine as the cause of the cursor lag after the file is already open.

## Cursor Placement Evidence

The slow interaction recorded in this run is cursor placement/clicking in the read-only merged preview pane. There were 13 slow `mouseDown` events:

```text
count=13 avg=122.0ms min=81.1ms max=335.0ms
```

Representative log lines:

```text
swift.log:11 - PERF input.textViewMouseDown elapsed_ms=116.4 blocks=253 rows=35159 gitMode=true previewMode=true pane=mergedSide clickCount=1 selection=16384:0 editable=false
swift.log:16 - PERF input.textViewMouseDown elapsed_ms=335.0 blocks=253 rows=35159 gitMode=true previewMode=true pane=mergedSide clickCount=1 selection=17242:94 editable=false
swift.log:23 - PERF input.textViewMouseDown elapsed_ms=126.6 blocks=253 rows=35159 gitMode=true previewMode=true pane=mergedSide clickCount=1 selection=28195:0 editable=false
```

No render logs appear between these mouse-down entries. That makes the immediate cursor lag look like AppKit/TextKit hit-testing, selection, or text layout work inside the huge read-only text view, rather than a fresh full diff render on every click.

## What This Run Does Not Prove

This run does not contain slow scroll logs. There are no `textViewScrollWheel`, `clipViewScrollWheel`, `horizontalScroll`, or `viewDidLayout` performance entries in the latest `swift.log`.

So the latest run proves slow cursor placement, and it proves a slow initial render. It does not yet prove where scroll slowness is happening. If scrolling felt slow during this run, either the slow work was below the current logging threshold, happened through an uninstrumented path, or did not emit because the reproduction mostly clicked rather than scrolled.

## Conclusions

1. The all-diff Git mode is now paying a real upfront Git status/listing cost in large repositories. In this run it was 2.4 seconds for 2,937 changed files.
2. Opening the selected changed file is much slower than the diff algorithm itself. Rendering 35,159 rows costs 3.8 seconds, while diff construction costs 92.3 ms.
3. The biggest render costs are `views` and `contentWidths`, together accounting for almost all render time.
4. The post-load cursor lag is happening in the Swift/AppKit text interaction layer. The slow `mouseDown` events occur after the C++ work is complete and without matching render events.
5. The app is currently treating a large Git diff preview like a fully materialized multi-pane text document. For a roughly 1 MB file and 35,159 rows, that is enough to make both initial render and basic cursor placement feel broken.

## Next Investigation Targets

No fixes were made in this pass.

For the next debugging pass, the most useful logs would be:

1. Break `textViewMouseDown` into sub-phases around `super.mouseDown`, selection updates, layout/display invalidation, and any visible-range calculations.
2. Add scroll-specific evidence if the slowdown is reproduced by scrolling: visible row range, event delta, synchronized scroll work, and whether AppKit asks TextKit to lay out far outside the visible range.
3. Record per-pane text sizes and rendered view counts when loading a Git diff preview, so the render cost can be tied to the exact amount of materialized UI.

## Render-Only Debug And Fix Analysis

Date: 2026-07-07

Log run inspected:

```text
/Users/golan.shabi/Library/Logs/mcdiff/2026-07-07:19:59:23_27995/
```

Files inspected:

```text
swift.log: 19 lines
cpp.log: 11 lines
```

### Issue

This pass only investigates why initial Git diff preview render is slow. Cursor placement and scrolling are intentionally ignored here.

The reproduction loaded `/Users/golan.shabi/git/orion`, selected `.gitlab-ci.yml`, and rendered a Git diff preview with 253 diff blocks and 35,159 rendered rows.

### Relevant Logs

The selected file load is dominated by render:

```text
swift.log:19 - PERF loadGitDiffFile total=4134.9ms path=.gitlab-ci.yml status=staged modified updateGitControls=231.8ms readHead=14.3ms readWorktree=1.2ms diff=91.3ms render=3796.4ms
```

Render breakdown:

```text
swift.log:18 - PERF render total=3794.2ms blocks=253 rows=35159 preserving=false contentWidths=943.7ms clearViews=0.0ms renderPlan=46.2ms views=2804.2ms refreshWidths=0.0ms restoreSelection=0.0ms
```

The C++ side built the diff document, but does not explain the render time:

```text
cpp.log:5 - Bridge requested diff left_chars=985256 right_chars=999378
cpp.log:8 - Built diff blocks=253
cpp.log:9 - Bridge produced document blocks=253
```

The width pass scans and measures nearly the whole file in all three panes:

```text
swift.log:8 - PERF contentWidths total=943.0ms sharedWidth=2909.0 leftSideLines=34650 leftSideChars=950606 leftSideMeasure=321.2ms mergedSideLines=35237 mergedSideChars=968798 mergedSideMeasure=303.7ms rightSideLines=35143 rightSideChars=964235 rightSideMeasure=300.7ms
```

View construction is almost entirely pane construction:

```text
swift.log:17 - PERF renderViews total=2801.7ms totalRows=35159 slots=253 leftPane=943.2ms mergedPane=913.7ms rightPane=939.3ms leftPickColumn=2.7ms rightPickColumn=2.6ms addSubviews=0.2ms equalWidthConstraints=0.0ms
```

Each pane is almost entirely `PaneTextClipView` setup:

```text
swift.log:12 - PERF renderPaneViews total=941.1ms pane=leftSide rows=35159 textLength=985764 lineNumberRows=35159 textClip=934.9ms
swift.log:14 - PERF renderPaneViews total=911.6ms pane=mergedSide rows=35159 textLength=981201 lineNumberRows=0 textClip=907.0ms
swift.log:16 - PERF renderPaneViews total=937.1ms pane=rightSide rows=35159 textLength=999393 lineNumberRows=35159 textClip=931.1ms
```

Inside `PaneTextClipView`, most time is full-text measuring plus attaching huge text views:

```text
swift.log:11 - leftSide textSize=2909.0x527385.0 measure=316.2ms attributed=0.0ms setStorage=16.1ms attach=596.2ms
swift.log:13 - mergedSide textSize=2909.0x527385.0 measure=308.2ms attributed=0.0ms setStorage=1.5ms attach=596.3ms
swift.log:15 - rightSide textSize=2909.0x527385.0 measure=315.0ms attributed=0.0ms setStorage=1.3ms attach=606.7ms
```

### Code Path

Render starts by measuring all pane content widths:

```text
App/MainWindowController_Rendering.swift:7 - updatePaneContentWidths()
App/MainWindowController_HorizontalScrolling.swift:73 - updatePaneContentWidths()
App/MainWindowController_HorizontalScrolling.swift:111 - measuredContentWidthDetails(for:)
```

That path calls `measuredLineWidth(_:)` for every candidate line in every pane:

```text
App/MainWindowController_HorizontalScrolling.swift:126 - for (blockIndex, block) in document.blocks.enumerated()
App/MainWindowController_HorizontalScrolling.swift:133 - for line in lines
App/MainWindowController_HorizontalScrolling.swift:188 - measuredLineWidth(_:)
```

The render plan then materializes full text arrays for each pane:

```text
App/MainWindowController_Rendering.swift:253 - renderPlan(for:)
App/MainWindowController_Rendering.swift:310 - panes[pane]?.textLines.append(contentsOf: lines)
```

Git diff preview does not use the existing equal-context compaction path:

```text
App/MainWindowController.swift:146 - rendersConflictContextOnly
App/MainWindowController.swift:150 - case .savePanel, .gitDiffPreview: return false
App/MainWindowController_Rendering.swift:429 - guard rendersConflictContextOnly, block.kind == .equal else
```

Because `gitDiffPreview` returns `false`, every equal block is rendered in full instead of passing through `compactedContextLines(...)`:

```text
App/MainWindowController_Rendering.swift:445 - let compacted = compactedContextLines(...)
```

Finally, each pane joins all lines into a large string and creates a full-height `PaneTextClipView`:

```text
App/MainWindowController_Rendering.swift:203 - var text = ""
App/MainWindowController_Rendering.swift:205 - text = content.textLines.joined(separator: "\n")
App/MainWindowController_Rendering.swift:208 - timed("textClip")
App/PaneViews.swift:419 - measuredSizeAndLineStats(for:)
App/PaneViews.swift:469 - addSubview(textView)
```

### Findings

The render delay is not caused by diff generation. Swift measured `diff=91.3ms`; render took `3796.4ms`.

The biggest direct render cause is that Git diff preview renders the whole before/after file into three full-height text views. The latest run created three text views around `2909.0x527385.0` points, each representing 35,159 lines.

The app pays for line measurement twice:

```text
contentWidths measurement:       321.2ms + 303.7ms + 300.7ms = 925.6ms
PaneTextClipView measure:        316.2ms + 308.2ms + 315.0ms = 939.4ms
combined repeated measurement:   about 1865.0ms
```

The single largest internal cost after measurement is attaching the huge text views:

```text
attach total: 596.2ms + 596.3ms + 606.7ms = 1799.2ms
```

The render plan itself is not the problem. It is only `46.2ms`, about 1.2% of the total render time.

Line numbers, pick columns, stack insertion, and equal-width constraints are also not material contributors in this run.

### How It Could Be Fixed

#### Fix 1: Use Existing Context Compaction For Git Diff Preview

The highest-leverage small fix is to let `.gitDiffPreview` use `rendersConflictContextOnly == true`, or introduce a separate flag such as `rendersUnchangedContextCompactly`.

Why this should help:

```text
Current render rows: 35159
Cause: all equal/unchanged blocks are rendered in full.
Existing compaction code: compactedContextLines(...)
```

This would preserve all changed blocks while collapsing large unchanged blocks to context rows with expansion controls. That matches standard unified-diff behavior more closely than rendering the whole file.

Expected impact: potentially large, because it reduces the number of rendered rows before both major costs happen:

```text
contentWidths scans fewer lines
PaneTextClipView measures fewer lines
NSTextView height is much smaller
attach cost should drop because the text views are no longer 527385 points tall
```

Risk: if "Git diff preview" must literally show the complete file contents at all times, this changes that behavior. If standard diff behavior is acceptable, this is the cleanest first fix because the compaction machinery already exists.

#### Fix 2: Reuse Text Measurement Between Widths And Text Clip Creation

The app currently measures widths in `updatePaneContentWidths()`, then measures again in `PaneTextClipView.init`.

The narrower optimization is to carry measured width, height, line count, and max line length from the content-width pass into `PaneTextClipView`, or compute it once as part of the render plan.

Expected impact: saves up to about `900ms` in this run. It will not remove the `~1800ms` attach cost, so this is useful but not sufficient alone.

Risk: low if implemented as cached render metadata and invalidated on every document/render-plan rebuild.

#### Fix 3: Read-Only Lightweight Git Preview Renderer

The structural fix is to avoid `NSTextView` for read-only Git diff preview. The current view is selectable/editable infrastructure being used for a read-only preview:

```text
PaneTextClipView -> PaneTextView -> NSTextView
```

A Git preview renderer could draw visible rows directly from `PaneRenderContent` using `NSView.draw(_:)`, computing the visible row range from `dirtyRect` and `lineHeight`. This would avoid:

```text
joining each pane into one giant String
building full attributed text storage
attaching full-height NSTextView instances
TextKit layout/hit-testing for non-editable preview text
```

Expected impact: largest long-term fix. It attacks both known render costs: full-text measurement and huge text-view attachment.

Risk: medium. It requires implementing selection/copy behavior separately if selectable text is required in preview mode.

### Recommended Order

1. First try context compaction for `.gitDiffPreview`, because it uses existing code and should reduce the row count before all expensive work.
2. Rerun the same `.gitlab-ci.yml` case and compare `rows`, `contentWidths`, `views`, and `renderTextClipInit.attach`.
3. If render is still too slow, add measurement reuse.
4. If large files are still slow after row reduction and measurement reuse, build the read-only lightweight renderer.

### Changes

No rendering behavior was changed in this pass.

This pass only updated the Markdown report with render-only debugging evidence and fix options.

### Verification

Commands used:

```text
ls -td /Users/golan.shabi/Library/Logs/mcdiff/*
wc -l /Users/golan.shabi/Library/Logs/mcdiff/2026-07-07:19:59:23_27995/swift.log /Users/golan.shabi/Library/Logs/mcdiff/2026-07-07:19:59:23_27995/cpp.log
rg -n "PERF (contentWidths|renderTrace|renderViews|renderPaneViews|render total|loadGitDiffFile)|renderTextClipInit" /Users/golan.shabi/Library/Logs/mcdiff/2026-07-07:19:59:23_27995/swift.log
nl -ba /Users/golan.shabi/Library/Logs/mcdiff/2026-07-07:19:59:23_27995/cpp.log
```

No build or test command was run because this pass only inspected logs/source and updated documentation.
