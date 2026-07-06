import AppKit
import Foundation

func testManualMergedEditEnablesSaveAndShowsManualText() throws {
    let files = try temporaryDirectory("manual-merged-edit")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    let insertion = ("alpha\n" as NSString).length
    replaceText(in: merged,
                range: NSRange(location: insertion, length: 0),
                with: "manual",
                "manual edit is accepted inside the changed block")
    layout(testWindow, controller)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "manual edit resolves the only changed block")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("manual"), "manual text appears in merged pane")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "mergedSide"), redAtLeast: 0.4, blueAtLeast: 0.4),
               "manual merged block uses a distinct middle-pane color")
}

func testSameLineManualMergedEditDoesNotRerenderTextView() throws {
    let files = try temporaryDirectory("manual-edit-no-rerender")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft side has enough width for manual edits\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright side has enough width for manual edits\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let initialMerged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists before manual edit")
        return
    }

    replaceText(in: initialMerged,
                range: NSRange(location: ("alpha\n" as NSString).length, length: 0),
                with: "manual",
                "first manual edit is accepted")
    layout(testWindow, controller)

    guard let afterFirstEdit = textViews(in: controller.view, identifier: "mergedSide").first,
          let manualRange = nsRange(of: "manual", in: afterFirstEdit.string) else {
        assertTrue(false, "manual text is rendered after first edit")
        return
    }
    assertTrue(afterFirstEdit === initialMerged, "first manual edit inside reserved conflict rows does not rebuild the text view")

    replaceText(in: afterFirstEdit,
                range: NSRange(location: NSMaxRange(manualRange), length: 0),
                with: "!",
                "same-line manual edit is accepted")
    layout(testWindow, controller)

    guard let afterSecondEdit = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after second edit")
        return
    }
    assertTrue(afterSecondEdit === afterFirstEdit, "same-line manual edit does not rebuild the text view")
    assertTrue(afterSecondEdit.string.contains("manual!"), "same-line manual edit updates text in place")
}

func testManualMergedEditUndoRedoRestoresBlockState() throws {
    let files = try temporaryDirectory("manual-edit-undo-redo")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: ("alpha\n" as NSString).length, length: 0),
                with: "manual",
                "manual edit is accepted before undo")
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("manual"),
               "manual text appears before undo")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == true,
               "manual text resolves the conflict before undo")

    undoMergedText(in: controller, "merged text view exists for manual edit undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "omega"],
               "undoing a manual edit restores the previous unpicked block state")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == false,
               "undoing a manual edit disables save when the conflict is unresolved again")

    redoMergedText(in: controller, "merged text view exists for manual edit redo")
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("manual"),
               "redoing a manual edit restores manual text")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == true,
               "redoing a manual edit resolves the conflict again")
}

func testUndoPreservesCaretInsideChangedBlock() throws {
    let files = try temporaryDirectory("changed-block-undo-caret")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft content\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright content\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    pickButton(in: controller.view, picksLeft: true)?.performClick(nil)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let leftRange = nsRange(of: "left content", in: merged.string) else {
        assertTrue(false, "picked left changed block is rendered before caret undo test")
        return
    }

    let insertion = NSRange(location: leftRange.location + ("left" as NSString).length, length: 0)
    replaceText(in: merged,
                range: insertion,
                with: "!",
                "edit inside picked changed block is accepted")
    layout(testWindow, controller)

    undoMergedText(in: controller, "merged text view exists for changed block caret undo")
    layout(testWindow, controller)

    guard let restored = textViews(in: controller.view, identifier: "mergedSide").first,
          let restoredLeftRange = nsRange(of: "left content", in: restored.string) else {
        assertTrue(false, "changed block text is restored after undo")
        return
    }

    let expectedCaret = restoredLeftRange.location + ("left" as NSString).length
    assertTrue(restored.selectedRange().location == expectedCaret,
               "undo inside a changed block keeps the caret at the edit point")
}

func testManualMergedEditNormalizesToRightPick() throws {
    let files = try temporaryDirectory("manual-normalizes-right")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    let insertion = ("alpha\n" as NSString).length
    replaceText(in: merged,
                range: NSRange(location: insertion, length: 0),
                with: "right",
                "typing the right block text is accepted")
    layout(testWindow, controller)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "typing the right side resolves the changed block")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("right"), "right text appears in merged pane")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), blueAtLeast: 0.7),
               "typing the right side normalizes to the same state as Use Right")
}

func testManualMergedEditCanBreakLineAtEndOfChangedLine() throws {
    let files = try temporaryDirectory("manual-break-end")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    let insertion = ("alpha\n" as NSString).length
    replaceText(in: merged,
                range: NSRange(location: insertion, length: 0),
                with: "manual",
                "manual edit is accepted before breaking the line")
    layout(testWindow, controller)

    guard let edited = textViews(in: controller.view, identifier: "mergedSide").first,
          let manualRange = nsRange(of: "manual", in: edited.string) else {
        assertTrue(false, "manual text is rendered before line break")
        return
    }
    replaceText(in: edited,
                range: NSRange(location: NSMaxRange(manualRange), length: 0),
                with: "\n",
                "line break is accepted at the end of the changed line")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "manual", "", "omega"],
               "line break at the end creates a real blank manual line")
}

func testRepeatedNewlineMergedEditDoesNotRerenderTextView() throws {
    let files = try temporaryDirectory("manual-newline-no-rerender")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let initialMerged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists before repeated newline edit")
        return
    }

    replaceText(in: initialMerged,
                range: NSRange(location: ("alpha\n" as NSString).length, length: 0),
                with: "\n",
                "first newline edit is accepted")
    layout(testWindow, controller)

    guard let afterFirstEdit = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after first newline edit")
        return
    }
    assertTrue(afterFirstEdit === initialMerged, "first newline edit grows rows without rebuilding the merged text view")

    replaceText(in: afterFirstEdit,
                range: afterFirstEdit.selectedRange(),
                with: "\n",
                "second newline edit is accepted")
    layout(testWindow, controller)

    guard let afterSecondEdit = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after second newline edit")
        return
    }
    assertTrue(afterSecondEdit === initialMerged, "repeated newline edit keeps the existing merged text view")
    assertTrue(controller.renderedBlockRows[1]?.rowCount == 3, "changed block row metadata grows inline")
    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "", "", "omega"],
               "merged pane keeps the inserted blank lines")
    assertTrue(textLines(in: controller.view, identifier: "leftSide") == ["alpha", "left", "", "", "omega"],
               "left pane receives alignment padding without a full rerender")
    assertTrue(textLines(in: controller.view, identifier: "rightSide") == ["alpha", "right", "", "", "omega"],
               "right pane receives alignment padding without a full rerender")

    undoMergedText(in: controller, "merged text view exists for repeated newline undo")
    layout(testWindow, controller)

    guard let afterUndo = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after repeated newline undo")
        return
    }
    assertTrue(afterUndo === initialMerged, "newline undo shrinks rows without rebuilding the merged text view")
    assertTrue(controller.renderedBlockRows[1]?.rowCount == 2, "changed block row metadata shrinks inline")
    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "", "omega"],
               "merged pane removes one inserted blank line")
}

func testRebreakingLineMergedFromChangedAndEqualRowsRestoresBoundary() throws {
    let files = try temporaryDirectory("rebreak-changed-equal")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "a\nb\nc\n".write(to: left, atomically: true, encoding: .utf8)
    try "A\nb\nc\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    pickButton(in: controller.view, picksLeft: true)?.performClick(nil)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let aRange = nsRange(of: "a", in: merged.string) else {
        assertTrue(false, "picked changed line is rendered before merging rows")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: NSMaxRange(aRange), length: 1),
                with: "",
                "deleting the newline after a merges b into the changed row")
    layout(testWindow, controller)

    let joinedLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(joinedLines.prefix(2).elementsEqual(["ab", "c"]),
               "deleting the boundary newline does not pull lower equal lines into the diff")
    let joinedChangedBlock = controller.document?.blocks.first
    let joinedEqualBlock = controller.document?.blocks.dropFirst().first
    assertTrue(joinedChangedBlock?.manualLines == ["ab"],
               "only the joined line becomes changed manual text")
    assertTrue(joinedEqualBlock?.manualLines == ["c"],
               "equal lines below the consumed line stay in the following block")
    let mergedPane = views(in: controller.view, identifier: "mergedSide")
        .compactMap { $0 as? PaneColumnView }
        .first
    assertTrue(mergedPane?.backgroundRuns.first?.rowCount == 1,
               "only the joined changed line is highlighted as diff")

    guard let joined = textViews(in: controller.view, identifier: "mergedSide").first,
          let abRange = nsRange(of: "ab", in: joined.string) else {
        assertTrue(false, "merged changed row contains ab before rebreaking")
        return
    }

    replaceText(in: joined,
                range: NSRange(location: abRange.location + ("a" as NSString).length, length: 0),
                with: "\n",
                "reinserting the newline splits the changed row")
    layout(testWindow, controller)

    let lines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(lines == ["a", "b", "c"],
               "b moves down one line without leaving a blank padding row")
    let changedBlock = controller.document?.blocks.first
    let equalBlock = controller.document?.blocks.dropFirst().first
    assertTrue(changedBlock?.pick == .left && (changedBlock?.manualLines ?? []).isEmpty,
               "changed block returns to the picked left line after rebreaking the boundary")
    assertTrue(equalBlock?.kind == .equal && equalBlock?.pick == .unpicked,
               "b returns to the following equal block instead of staying in the diff")

    undoMergedText(in: controller, "merged text view exists for boundary rebreak undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide").prefix(2).elementsEqual(["ab", "c"]),
               "undoing the rebreak restores the joined changed row and remaining equal line")

    redoMergedText(in: controller, "merged text view exists for boundary rebreak redo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["a", "b", "c"],
               "redoing the rebreak restores the changed/equal boundary")
}

func testAllBlankRowsInDeletionBlockAreEditable() throws {
    let files = try temporaryDirectory("blank-deletion-rows-editable")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "one\ntwo\nthree\n".write(to: left, atomically: true, encoding: .utf8)
    try "".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["", "", ""],
               "deletion block reserves every merged row as editable empty text")
    replaceText(in: merged,
                range: NSRange(location: merged.string.count, length: 0),
                with: "last",
                "editing the last empty row in the changed block is accepted")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["", "", "last"],
               "last empty row in the changed block can receive text")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "editing an empty row resolves the deletion block")
}

func testMergedPaneAcceptsMultiLinePasteText() throws {
    let files = try temporaryDirectory("paste-text")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: ("alpha\n" as NSString).length, length: 0),
                with: "pasted\ntext",
                "multi-line paste text is accepted in the changed block")
    layout(testWindow, controller)

    let mergedText = text(in: controller.view, identifier: "mergedSide")
    assertTrue(mergedText.contains("pasted"), "paste inserts text into the merged pane")
    assertTrue(mergedText.contains("text"), "paste supports multi-line text")
}

func testMergedEditAllowsEqualRows() throws {
    let files = try temporaryDirectory("manual-allows-equal")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nbeta\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nbeta\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let alphaRange = nsRange(of: "alpha", in: merged.string) else {
        assertTrue(false, "merged pane renders equal alpha text")
        return
    }

    replaceText(in: merged,
                range: alphaRange,
                with: "changed",
                "equal rows accept editing")
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("changed"),
               "equal-row edit appears in merged pane")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "manual equal-row edit can be saved")
}

func testNewlineEditInEqualRowsKeepsCaretVisible() throws {
    let files = try temporaryDirectory("equal-newline-caret")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nbeta\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nbeta\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let initialMerged = textViews(in: controller.view, identifier: "mergedSide").first,
          let alphaRange = nsRange(of: "alpha", in: initialMerged.string) else {
        assertTrue(false, "merged pane renders equal alpha text")
        return
    }

    let insertion = NSRange(location: NSMaxRange(alphaRange), length: 0)
    replaceText(in: initialMerged,
                range: insertion,
                with: "\n",
                "equal row accepts newline edit")
    layout(testWindow, controller)

    guard let afterEdit = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after equal newline edit")
        return
    }
    assertTrue(afterEdit === initialMerged, "equal row newline edit keeps the existing text view")
    assertTrue(afterEdit.selectedRange().location == insertion.location + 1,
               "caret remains at the insertion point after equal row newline edit")
    assertTrue(controller.view.window?.firstResponder === afterEdit,
               "merged text view remains first responder after equal row newline edit")
    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "beta"],
               "equal row newline edit updates merged text in place")
}

func testUndoPreservesCaretInsideEqualRows() throws {
    let files = try temporaryDirectory("equal-row-undo-caret")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "one\ntwo words\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "one\ntwo words\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let twoRange = nsRange(of: "two words", in: merged.string) else {
        assertTrue(false, "equal row is rendered before caret undo test")
        return
    }

    let insertion = NSRange(location: twoRange.location + ("two" as NSString).length, length: 0)
    replaceText(in: merged,
                range: insertion,
                with: "!",
                "edit inside equal row is accepted")
    layout(testWindow, controller)

    undoMergedText(in: controller, "merged text view exists for equal row caret undo")
    layout(testWindow, controller)

    guard let restored = textViews(in: controller.view, identifier: "mergedSide").first,
          let restoredTwoRange = nsRange(of: "two words", in: restored.string) else {
        assertTrue(false, "equal row text is restored after undo")
        return
    }

    let expectedCaret = restoredTwoRange.location + ("two" as NSString).length
    assertTrue(restored.selectedRange().location == expectedCaret,
               "undo inside equal rows keeps the caret at the edit point")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == false,
               "undoing equal-row edit leaves the unresolved changed block unresolved")
}

func testEditingEqualLineAboveConflictDoesNotResolveConflict() throws {
    let files = try temporaryDirectory("equal-above-conflict")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "one\ntwo\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "one\ntwo\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let twoRange = nsRange(of: "two", in: merged.string) else {
        assertTrue(false, "merged pane renders equal line above conflict")
        return
    }

    replaceText(in: merged,
                range: twoRange,
                with: "TWO",
                "editing equal line above a conflict is accepted")
    layout(testWindow, controller)

    let lines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(lines == ["one", "TWO", "", "omega"],
               "editing equal line above conflict does not move text into the conflict block")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "editing equal line above conflict does not resolve the conflict")
}

func testEditingAtEndOfEqualLineAboveConflictDoesNotResolveConflict() throws {
    let files = try temporaryDirectory("equal-end-above-conflict")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "one\ntwo\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "one\ntwo\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let oneRange = nsRange(of: "one", in: merged.string),
          nsRange(of: "two", in: merged.string) != nil else {
        assertTrue(false, "merged pane renders equal lines above conflict")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: NSMaxRange(oneRange), length: 0),
                with: "!",
                "editing at end of equal line two rows above conflict is accepted")
    layout(testWindow, controller)

    guard let afterFirstEdit = textViews(in: controller.view, identifier: "mergedSide").first,
          let updatedTwoRange = nsRange(of: "two", in: afterFirstEdit.string) else {
        assertTrue(false, "merged pane renders second equal line after first edit")
        return
    }
    replaceText(in: afterFirstEdit,
                range: NSRange(location: NSMaxRange(updatedTwoRange), length: 0),
                with: "!",
                "editing at end of equal line directly above conflict is accepted")
    layout(testWindow, controller)

    let lines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(lines == ["one!", "two!", "", "omega"],
               "end-of-line edits above conflict stay in the equal block")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "end-of-line edits above conflict do not resolve the conflict")
}

func testMergedEditCanSpanMultipleBlocks() throws {
    let files = try temporaryDirectory("manual-cross-block")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: 0, length: (merged.string as NSString).length),
                with: "whole",
                "edit spanning equal, changed, and equal blocks is accepted")
    layout(testWindow, controller)

    let mergedText = text(in: controller.view, identifier: "mergedSide")
    assertTrue(mergedText.contains("whole"), "cross-block edit appears in merged pane")
    assertTrue(!mergedText.contains("alpha"), "cross-block edit removes old first equal text")
    assertTrue(!mergedText.contains("omega"), "cross-block edit removes old last equal text")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "cross-block edit resolves affected changed block")
}

func testCrossBlockMergedEditUndoRestoresEveryAffectedBlock() throws {
    let files = try temporaryDirectory("cross-block-undo")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    replaceText(in: merged,
                range: NSRange(location: 0, length: (merged.string as NSString).length),
                with: "whole",
                "cross-block edit is accepted before undo")
    layout(testWindow, controller)

    let editedText = text(in: controller.view, identifier: "mergedSide")
    assertTrue(editedText.contains("whole"), "cross-block edit inserts replacement text before undo")
    assertTrue(!editedText.contains("alpha") && !editedText.contains("omega"),
               "cross-block edit removes old equal text before undo")

    undoMergedText(in: controller, "merged text view exists for cross-block undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "omega"],
               "undoing a cross-block edit restores equal text and the unresolved changed row")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == false,
               "undoing a cross-block edit restores the unresolved changed block")
}

func testDeletingManualMergedTextLeavesResolvedEmptyBlock() throws {
    let files = try temporaryDirectory("manual-delete-empty")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let unpicked = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists")
        return
    }

    let insertion = ("alpha\n" as NSString).length
    replaceText(in: unpicked,
                range: NSRange(location: insertion, length: 0),
                with: "manual",
                "manual edit is accepted before deleting it")
    layout(testWindow, controller)

    guard let edited = textViews(in: controller.view, identifier: "mergedSide").first,
          let manualRange = nsRange(of: "manual", in: edited.string) else {
        assertTrue(false, "manual text is rendered before deletion")
        return
    }
    replaceText(in: edited,
                range: manualRange,
                with: "",
                "deleting all manual text is accepted")
    layout(testWindow, controller)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "empty manual edit still resolves the changed block")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("manual"),
               "manual text is removed from the merged pane")
}

func testPaneUsesOneNativeSelectionAcrossMultipleTextBlocks() throws {
    let files = try temporaryDirectory("multi-block-selection")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "one\nleft first\nmiddle\nleft second\nend\n".write(to: left, atomically: true, encoding: .utf8)
    try "one\nright first\nmiddle\nright second\nend\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let textView = textViews(in: controller.view, identifier: "leftSide").first,
          let firstRange = textView.string.range(of: "left first"),
          let secondRange = textView.string.range(of: "left second") else {
        assertTrue(false, "left pane renders both changed text blocks in one native text view")
        return
    }

    let firstNSRange = NSRange(firstRange, in: textView.string)
    let secondNSRange = NSRange(secondRange, in: textView.string)
    let selection = NSRange(location: firstNSRange.location,
                            length: secondNSRange.location + secondNSRange.length - firstNSRange.location)
    textView.setSelectedRange(selection)

    assertTrue(textView.selectedRange() == selection, "native text view keeps a selection across changed blocks")
    let selectedText = (textView.string as NSString).substring(with: textView.selectedRange())
    assertTrue(selectedText.contains("left first"), "selection includes first changed block")
    assertTrue(selectedText.contains("middle"), "selection crosses the equal block between changes")
    assertTrue(selectedText.contains("left second"), "selection includes second changed block")
}

func testNativeTextSelectionKeepsPartialWordRange() throws {
    let files = try temporaryDirectory("partial-word-selection")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha beta gamma\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha beta gamma\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let textView = textViews(in: controller.view, identifier: "leftSide")
        .first(where: { $0.string.contains("alpha beta gamma") }),
          let betaRange = textView.string.range(of: "beta") else {
        assertTrue(false, "left pane renders selectable text containing beta")
        return
    }

    textView.setSelectedRange(NSRange(betaRange, in: textView.string))

    let selectedText = (textView.string as NSString).substring(with: textView.selectedRange())
    assertTrue(selectedText == "beta", "native partial-word selection keeps the exact selected word")
    assertTrue(views(in: controller.view, identifier: "leftSideSelectionOverlay").isEmpty,
               "partial selection uses TextKit instead of a custom overlay")
}

func testPickingOneBlockLeavesOtherMergedBlocksBlankAndUnsaved() throws {
    let files = try temporaryDirectory("multi-change-files")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "a\nleft1\nb\nleft2\nc\n".write(to: left, atomically: true, encoding: .utf8)
    try "a\nright1\nb\nright2\nc\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["a", "", "b", "", "c"],
               "both unpicked changed blocks start blank in the merged pane")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)

    let mergedText = text(in: controller.view, identifier: "mergedSide")
    assertTrue(mergedText.contains("right1"), "first picked block updates merged pane")
    assertTrue(!mergedText.contains("left1"), "first picked block no longer shows old text in merged pane")
    assertTrue(textLines(in: controller.view, identifier: "mergedSide").contains(""), "second unpicked block remains blank")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "second unpicked block keeps save disabled")
}

func testPickingSmallerConflictKeepsLeftAndRightRowsVisible() throws {
    let files = try temporaryDirectory("smaller-pick-keeps-sides")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "same\nleft one\nleft two\nleft three\ntail\n".write(to: left, atomically: true, encoding: .utf8)
    try "same\nright one\ntail\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "", "", "", "tail"],
               "unpicked conflict reserves blank rows for the larger side")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "right one", "", "", "tail"],
               "picking the smaller side keeps changed block rows visible")
    assertTrue(textLines(in: controller.view, identifier: "leftSide") == ["same", "left one", "left two", "left three", "tail"],
               "picking right does not remove the longer left side from view")
    assertTrue(textLines(in: controller.view, identifier: "rightSide") == ["same", "right one", "", "", "tail"],
               "right pane stays aligned with the full changed block")

    guard let merged = textViews(in: controller.view, identifier: "mergedSide").first,
          let rightRange = nsRange(of: "right one", in: merged.string) else {
        assertTrue(false, "picked smaller right side is editable")
        return
    }
    replaceText(in: merged,
                range: NSRange(location: NSMaxRange(rightRange), length: 0),
                with: "!",
                "editing picked smaller right side is accepted")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "right one!", "", "", "tail"],
               "editing the smaller picked side keeps only alignment padding rows")
    undoMergedText(in: controller, "merged text view exists for smaller picked side undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "right one", "", "", "tail"],
               "undoing an edit in the smaller picked side does not append padding as content")
    undoMergedText(in: controller, "merged text view exists for smaller right pick undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "", "", "", "tail"],
               "undoing the smaller right pick restores padding rows without growing the block")
}
