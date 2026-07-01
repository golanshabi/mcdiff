# Middle Panel Editing Design

## Goal

Allow the user to type directly in the middle merged panel while still seeing the
left and right inputs beside it. Picking `Use Left` or `Use Right` remains the
fast path, but manually typing the exact left or right text should produce the
same model state and saved output as pressing the matching button.

This should stay native and small. The existing `NSTextView`/TextKit rendering
should remain the editor surface, and the existing libgit2-based diff engine
should remain the source for diff information.

## Current Shape

The app currently has three rendered panes:

- `left`: read-only text from `MDBlock.leftLines`.
- `merged`: read-only text derived from the block pick state.
- `right`: read-only text from `MDBlock.rightLines`.

`MainWindowController` builds a `RenderPlan` from `MDDocument.blocks`, pads the
pane text lines so rows stay aligned, and renders one native `NSTextView` per
pane inside `PaneTextClipView`.

Changed blocks currently have only three states:

- `unpicked`: middle pane shows blank rows and save is disabled.
- `left`: middle pane shows `leftLines`.
- `right`: middle pane shows `rightLines`.

Saving goes through `MDDocument.mergedText()`, which converts the Objective-C
bridge objects back to C++ `DiffDocument` and calls `macdiff::mergeText`.

## Proposed User Behavior

1. The first implementation should make changed blocks editable.
2. The design should not assume this forever. A later change should be able to
   make unchanged/equal blocks editable too. If that falls out naturally during
   implementation, it can be included; if it adds meaningful complexity, defer
   it.
3. Equal rows may remain read-only in the first version so conflict editing can
   land safely without becoming a full merged-file editor.
4. Typing, deleting, and replacing text inside a changed block creates a manual
   merged version for that block.
5. If the manual text becomes byte-for-byte equal to the left block text, the
   block becomes `left`, exactly like pressing `Use Left`.
6. If the manual text becomes byte-for-byte equal to the right block text, the
   block becomes `right`, exactly like pressing `Use Right`.
7. If the manual text is different from both sides, the block is a valid manual
   resolution and save is enabled once every changed block is resolved.
8. `Cmd+Z` support should be designed in, but it can be implemented after the
   first editable version.

## Data Model

Add a real manual resolution state instead of overloading `unpicked`.

Recommended C++ model:

```cpp
enum class PickSide { Invalid, Unpicked, Left, Right, Manual };

struct DiffBlock {
    DiffBlockKind kind = DiffBlockKind::Invalid;
    std::vector<std::string> leftLines;
    std::vector<std::string> rightLines;
    std::vector<std::string> manualLines;
    LineNumber leftStartLine = InvalidLineNumber;
    LineNumber rightStartLine = InvalidLineNumber;
    PickSide pick = PickSide::Unpicked;
};
```

Recommended bridge model:

```objc
typedef NS_ENUM(NSInteger, MDPickSide) {
    MDPickSideUnpicked,
    MDPickSideLeft,
    MDPickSideRight,
    MDPickSideManual
};

@interface MDBlock : NSObject
@property MDBlockKind kind;
@property (copy) NSArray<NSString *> *leftLines;
@property (copy) NSArray<NSString *> *rightLines;
@property (copy) NSArray<NSString *> *manualLines;
@property NSInteger leftStartLine;
@property NSInteger rightStartLine;
@property MDPickSide pick;
@end
```

`manualLines` is meaningful only when `pick == MDPickSideManual` in the first
version. Keep the name generic enough that manual equal-block edits can use the
same field later. Pick buttons clear `manualLines` and set `pick` to `.left` or
`.right`.

Save readiness becomes:

- Equal blocks are always resolved.
- Changed blocks are resolved when `pick` is `.left`, `.right`, or `.manual`.
- Changed blocks with `.unpicked` still block saving.

Merge output becomes:

- Equal: append `leftLines`.
- Left: append `leftLines`.
- Right: append `rightLines`.
- Manual: append `manualLines`.
- Unpicked: throw the existing "Choose a side" error.

If full merged-file editing becomes part of the first implementation, `Manual`
should be allowed for equal blocks too. Otherwise equal blocks can keep the
current append-`leftLines` behavior until that later feature.

## Normalization

After each accepted edit to a changed block:

1. Convert the edited middle block text to `[String]` using the same line model
   as the diff engine: lines do not include their trailing newline.
2. Compare that array to `leftLines`.
3. Compare that array to `rightLines`.
4. Update the block:

```swift
if editedLines == block.leftLines {
    block.pick = .left
    block.manualLines = []
} else if editedLines == block.rightLines {
    block.pick = .right
    block.manualLines = []
} else {
    block.pick = .manual
    block.manualLines = editedLines
}
```

This is the rule that makes typing a side equivalent to pressing the side's
button.

## UI Architecture

Keep the existing native text path:

- Continue using `NSTextView` for text display, selection, keyboard editing,
  clipboard behavior, and future undo support.
- Continue using `PaneColumnView` for block background runs.
- Continue using the existing custom horizontal slider logic so long lines keep
  moving all panes together.

Add a middle-pane edit coordinator in `MainWindowController`:

```swift
private struct MergedBlockTextRange {
    var blockIndex: Int
    var lineRange: Range<Int>
    var characterRange: NSRange
    var isEditable: Bool
}
```

`RenderPlan` should include middle-pane block ranges in addition to text lines
and background runs. The ranges map rendered middle text back to source blocks.

`PaneTextClipView` should expose enough configuration to create an editable
middle text view without changing the left and right panes:

- `isEditable`
- `allowsUndo`
- `delegate`
- maybe `textView` as a read-only property

The left and right panes stay read-only.

## Edit Validation

Use `NSTextViewDelegate` or an `NSTextView` subclass to validate edits before
TextKit applies them.

Current implementation direction:

- Allow edits in every middle-pane range, including equal blocks.
- Allow edits spanning multiple rendered diff blocks.
- Store same-as-left edits as normal equal/left state where possible.
- Store changed equal rows, custom conflict rows, and cross-block replacements
  as manual output.

A cross-block edit means one text operation touches more than one rendered block.
Examples:

- Selecting from the end of one changed block into the equal context after it
  and pressing Delete.
- Selecting text from one conflict through the next conflict and replacing it.
- Pressing Backspace at the first character of a block when the caret would
  merge it with the previous block.

When a cross-block edit replaces several rendered blocks, the replacement text
is assigned to the first affected block and the other affected blocks become
empty manual output. This preserves saved output order while keeping the
existing block-based renderer.

## Updating The Model From TextKit

After TextKit accepts an edit:

1. Find the affected changed block from the stored range map.
2. Read that block's current middle text from the full middle pane string.
3. Convert it to lines.
4. Apply normalization.
5. Update save button state.
6. Re-render only if needed.

Re-render is needed when:

- The block's line count changes.
- Normalization changes the pick state.
- Background coloring needs to reflect a new state.

For ordinary same-line typing, avoid rebuilding the full view on every
keystroke. The native text view already contains the edited text; the model can
sync immediately while layout refresh waits until it is needed.

Model sync can happen after every accepted text edit. That should be efficient
because the coordinator only touches the affected block, not the whole document.
The expensive parts should not run for every key:

- Full re-render should happen only when line count, pick state, or visible
  styling actually changes.
- Local visual diff should be computed only for the affected block.
- Intraline diff highlighting should be delayed until the basic editor is
  stable, or throttled/debounced if it is added early.

For examples like `AA` vs `A`, `A` vs `AA`, and `AB` vs `AA`, the line-level
diff tells us which rendered lines correspond. A later intraline pass can then
mark the deleted, inserted, or changed characters. Prefer Swift's standard
`CollectionDifference` over a custom character-diff algorithm unless it proves
insufficient.

When a re-render happens, preserve:

- Vertical scroll position.
- Shared horizontal offset.
- First responder.
- Selection/caret position relative to the edited block.

## Row Alignment

The current renderer pads pane text lines to the block's `rowCount`. Keep that
visual approach, but do not treat padding as editable middle text. The middle
pane should not contain fake empty lines just to make alignment work.

Compute `rowCount` from all three visible sides:

- Equal block: max left/right line count, normally the same.
- Unpicked changed block: max left/right line count, at least 1.
- Left pick: max left line count, at least 1.
- Right pick: max right line count, at least 1.
- Manual pick: max left/right/manual line count, at least 1.

Manual edits that add or remove lines will therefore expand or shrink the
changed block while keeping the left and right panes aligned.

Important distinction:

- Real blank lines typed by the user are document content.
- Blank rows needed only for alignment are layout, not text, and must not be
  selectable, editable, or saved.
- If the current single-string renderer needs padding lines, those lines must be
  marked as non-editable layout rows and stripped before syncing a block back to
  `manualLines`.

## Visual Diff State

Minimum version:

- Left changed side keeps its existing red background.
- Right changed side keeps its existing green background.
- Picked left or right side keeps the existing blue selected-side background.
- Middle unpicked blocks keep the existing unresolved color.
- Middle manual blocks get a distinct neutral/manual color.

Useful next version:

- For manual blocks, compute a local diff of `leftLines` vs `manualLines` and
  `manualLines` vs `rightLines` using the existing libgit2 diff path.
- Use those local results to add row-level background runs showing which manual
  lines differ from left, right, or both.
- Add intraline highlights after row-level diff is stable, using TextKit
  attributes on changed character ranges.

Block-level coloring is enough for the first version. Row-level and intraline
diff rendering are good follow-ups, but they should not block the first editable
middle pane.

## Existing Libraries To Reuse

Use what is already in the project:

- AppKit `NSTextView` and TextKit for editing, selection, clipboard behavior,
  font metrics, key handling, and future undo.
- AppKit `NSUndoManager` for future `Cmd+Z` support.
- libgit2 `git_diff_buffers`, already wrapped by `Core/DiffEngine.cpp`, for any
  left-middle and middle-right local diff calculations.
- Foundation/Objective-C bridging for moving line arrays between Swift and C++.

Do not introduce a web editor, custom text engine, or a new third-party diff
library for this feature.

## Undo Direction

Undo is implemented at the merge-model level with AppKit `UndoManager` rather
than by relying on `NSTextView`'s text-storage undo. The middle text view is
rebuilt after each accepted edit, so the durable undo unit is the affected block
state, not the temporary editor contents.

- All side picks and text edits flow through the controller before mutating the
  bridge model.
- Before each mutation, the controller stores `MergedBlockSnapshot` values with
  `blockIndex`, `pick`, and `manualLines`.
- `Cmd+Z` and `Shift+Cmd+Z` route through the middle `NSTextView`/responder
  chain into the controller's `UndoManager`.
- Restoring a snapshot writes `pick/manualLines` back to the bridge objects,
  re-renders the middle pane, and updates save readiness.

If full-file editing is added later, storing the whole previous `DiffBlock` (or
a document-level snapshot for larger edits) will be safer than extending this
snapshot one field at a time.

## Suggested Implementation Steps

1. Extend `PickSide`/`MDPickSide` with `Manual` and add `manualLines`.
2. Update bridge conversion, `canSave`, `mergeText`, and core tests.
3. Extend `RenderPlan` with middle-pane block range metadata.
4. Separate editable middle text ranges from layout-only padding rows.
5. Make the middle pane `NSTextView` editable while keeping left/right read-only.
6. Add edit mapping for equal rows and cross-block ranges.
7. Sync accepted edits back to the block model and normalize left/right matches.
8. Update render colors for manual blocks.
9. Add Swift tests for typing, deleting, left/right normalization, save
   readiness, equal-row edits, and cross-block edits.
10. Add optional local left-middle and middle-right diff rendering after the basic
   editor behavior is solid.

## Test Plan

Core tests:

- Manual changed block merges `manualLines`.
- Manual empty block can merge to deletion.
- Unpicked changed block still cannot merge.
- Manual lines equal to left/right are normalized before bridge save.

Swift/UI tests:

- Middle pane is editable; left and right panes remain read-only.
- Equal middle rows accept typing and save as manual output when changed.
- Changed middle row accepts typing and enables save when all conflicts are
  resolved.
- Deleting all text inside a changed block creates a valid manual empty block.
- Typing exactly the left side sets the same state/output as `Use Left`.
- Typing exactly the right side sets the same state/output as `Use Right`.
- Manual block with more lines expands row alignment across all panes.
- Manual block with fewer lines shrinks row alignment without hiding left/right
  context.
- Layout-only padding rows are not saved as blank manual lines.
- Selection/caret survives required re-renders.
- Horizontal scroll offset survives editing and picking.

## Resolved Direction From Review

1. Editing should eventually cover the whole middle pane. For the first version,
   do changed blocks only unless full editing is clearly simple. Implemented:
   editing now covers the whole middle pane.
2. Cross-block edits are text operations whose range touches more than one diff
   block. Implemented: these edits are accepted and mapped to manual output.
3. Block-level manual coloring is enough for the first version.
4. The middle pane should not show or save fake empty padding lines. Alignment
   rows are layout only.
