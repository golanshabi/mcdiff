import AppKit
import Foundation

func testLongLineSlidersMoveAllPanesTogetherWithoutChangingPaneWidths() throws {
    let files = try temporaryDirectory("long-lines")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    let longLine = String(repeating: "This is a long sentence with many words. ", count: 12)
    try "alpha\n\(longLine)\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nshort\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    assertTrue(scrollView(in: controller.view, identifier: "verticalScroll")?.hasHorizontalScroller == false,
               "outer scroll view is vertical-only")

    let leftWidthsBefore = paneWidths(in: controller.view, identifier: "leftSide")
    let mergedWidthsBefore = paneWidths(in: controller.view, identifier: "mergedSide")
    let rightWidthsBefore = paneWidths(in: controller.view, identifier: "rightSide")
    assertStableWidths(leftWidthsBefore, "left pane widths start stable")
    assertStableWidths(mergedWidthsBefore, "merged pane widths start stable")
    assertStableWidths(rightWidthsBefore, "right pane widths start stable")

    guard let leftScroller = horizontalControl(in: controller.view, identifier: "leftSideHorizontalScroller") else {
        assertTrue(false, "left horizontal control exists")
        return
    }
    guard let mergedScroller = horizontalControl(in: controller.view, identifier: "mergedSideHorizontalScroller") else {
        assertTrue(false, "merged horizontal control exists")
        return
    }
    guard let rightScroller = horizontalControl(in: controller.view, identifier: "rightSideHorizontalScroller") else {
        assertTrue(false, "right horizontal control exists")
        return
    }
    assertTrue(leftScroller.isEnabled, "left pane enables horizontal scrolling for long line")
    assertTrue(mergedScroller.isEnabled, "merged pane shares horizontal scrolling for long line")
    assertTrue(rightScroller.isEnabled, "right pane shares horizontal scrolling for long line")

    leftScroller.doubleValue = 1
    sendSliderAction(leftScroller)
    layout(testWindow, controller)

    let leftOriginsAfter = textLabelOrigins(in: controller.view, clipIdentifier: "leftSideTextClip")
    let mergedOriginsAfter = textLabelOrigins(in: controller.view, clipIdentifier: "mergedSideTextClip")
    let rightOriginsAfter = textLabelOrigins(in: controller.view, clipIdentifier: "rightSideTextClip")
    assertTrue(!leftOriginsAfter.isEmpty, "left text clips exist")
    assertTrue(!mergedOriginsAfter.isEmpty, "merged text clips exist")
    assertTrue(!rightOriginsAfter.isEmpty, "right text clips exist")
    assertTrue(leftOriginsAfter.allSatisfy { $0 < -1 }, "left slider moves every left row horizontally")
    assertTrue(mergedOriginsAfter.allSatisfy { $0 < -1 }, "left slider also moves every merged row horizontally")
    assertTrue(rightOriginsAfter.allSatisfy { $0 < -1 }, "left slider also moves every right row horizontally")
    assertTrue(mergedScroller.doubleValue == leftScroller.doubleValue, "merged slider value follows left slider")
    assertTrue(rightScroller.doubleValue == leftScroller.doubleValue, "right slider value follows left slider")
    assertTrue(paneWidths(in: controller.view, identifier: "leftSide") == leftWidthsBefore,
               "left pane visible widths remain constant after horizontal scroll")
    assertTrue(paneWidths(in: controller.view, identifier: "mergedSide") == mergedWidthsBefore,
               "merged pane visible widths remain constant after horizontal scroll")
    assertTrue(paneWidths(in: controller.view, identifier: "rightSide") == rightWidthsBefore,
               "right pane visible widths remain constant after horizontal scroll")

    pickButton(in: controller.view, picksLeft: true)?.performClick(nil)
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains(longLine),
               "picking left updates merged pane to long content")
    assertTrue(textLabelOrigins(in: controller.view, clipIdentifier: "leftSideTextClip").allSatisfy { $0 < -1 },
               "left horizontal offset survives pick re-render")
    assertTrue(textLabelOrigins(in: controller.view, clipIdentifier: "mergedSideTextClip").allSatisfy { $0 < -1 },
               "merged horizontal offset survives pick re-render")
    assertTrue(textLabelOrigins(in: controller.view, clipIdentifier: "rightSideTextClip").allSatisfy { $0 < -1 },
               "right horizontal offset survives pick re-render")
}

func testMainWindowGitMergeToolSaveWritesMergedPath() throws {
    let files = try temporaryDirectory("git-mergetool-save")
    let base = files.appendingPathComponent("base.txt")
    let local = files.appendingPathComponent("local.txt")
    let remote = files.appendingPathComponent("remote.txt")
    let merged = files.appendingPathComponent("merged.txt")
    try "base\n".write(to: base, atomically: true, encoding: .utf8)
    try "ours\n".write(to: local, atomically: true, encoding: .utf8)
    try "theirs\n".write(to: remote, atomically: true, encoding: .utf8)
    try """
    before
    <<<<<<< HEAD
    ours
    =======
    theirs
    >>>>>>> branch
    after

    """.write(to: merged, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    var completed: Bool?
    controller.mergeToolCompletionHandler = { completed = $0 }
    controller.loadGitMergeTool(base: base, local: local, remote: remote, merged: merged)
    layout(testWindow, controller)

    assertTrue(buttons(in: controller.view).first { $0.title == "Save Merge" }?.isEnabled == false,
               "mergetool save starts disabled before resolution")
    assertTrue(labels(in: controller.view).contains { $0.identifier?.rawValue == "gitStatusLabel" && !$0.isHidden },
               "mergetool shows git status")
    assertTrue(text(in: controller.view, identifier: "leftSide").contains("ours"), "mergetool renders local side")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("theirs"), "mergetool renders remote side")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)
    let save = buttons(in: controller.view).first { $0.title == "Save Merge" }
    assertTrue(save?.isEnabled == true, "mergetool save enables after resolution")
    save?.performClick(nil)

    assertTrue(completed == true, "mergetool reports successful completion after save")
    let saved = try String(contentsOf: merged, encoding: .utf8)
    assertTrue(saved == "before\ntheirs\nafter\n", "mergetool writes resolved output to merged path")
}

func testMainWindowGitMergeToolCompactsLargeContextAndPreservesSave() throws {
    let files = try temporaryDirectory("git-mergetool-compact-context")
    let base = files.appendingPathComponent("base.txt")
    let local = files.appendingPathComponent("local.txt")
    let remote = files.appendingPathComponent("remote.txt")
    let merged = files.appendingPathComponent("merged.txt")
    try "base\n".write(to: base, atomically: true, encoding: .utf8)
    try "ours\n".write(to: local, atomically: true, encoding: .utf8)
    try "theirs\n".write(to: remote, atomically: true, encoding: .utf8)

    let beforeLines = (1...350).map { "before \($0)" }
    let afterLines = (1...3).map { "after \($0)" }
    let conflicted = (beforeLines + [
        "<<<<<<< HEAD",
        "ours",
        "=======",
        "theirs",
        ">>>>>>> branch"
    ] + afterLines).joined(separator: "\n") + "\n"
    try conflicted.write(to: merged, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    var completed: Bool?
    controller.mergeToolCompletionHandler = { completed = $0 }
    controller.loadGitMergeTool(base: base, local: local, remote: remote, merged: merged)
    layout(testWindow, controller)

    let visibleLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(visibleLines.count < beforeLines.count + afterLines.count,
               "mergetool renders compact conflict context")
    assertTrue(visibleLines.contains("⋯"),
               "mergetool shows an obvious collapsed context band")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Show"),
               "merged text body does not contain textual expansion controls")
    let leftGutterLabel = views(in: controller.view, identifier: "leftSideLineNumbers")
        .first?
        .accessibilityLabel() ?? ""
    assertTrue(leftGutterLabel.contains("↑") &&
               leftGutterLabel.contains("↕") &&
               leftGutterLabel.contains("↓"),
               "line number gutter renders icon-only expansion controls")
    assertTrue(!visibleLines.contains("before 150"),
               "middle unchanged context is not rendered")

    guard let mergedView = textViews(in: controller.view, identifier: "mergedSide").first,
          let omittedRange = nsRange(of: "⋯", in: mergedView.string) else {
        assertTrue(false, "compact omitted context is visible")
        return
    }
    replaceText(in: mergedView,
                range: omittedRange,
                with: "changed",
                shouldAllow: false,
                "omitted context is read-only")
    guard let visibleEqualRange = nsRange(of: "before 1", in: mergedView.string) else {
        assertTrue(false, "visible unchanged context is editable")
        return
    }
    replaceText(in: mergedView,
                range: visibleEqualRange,
                with: "edited before 1",
                "visible unchanged context is editable")
    guard let afterEqualEdit = textViews(in: controller.view, identifier: "mergedSide").first,
          let editedRange = nsRange(of: "edited before 1", in: afterEqualEdit.string) else {
        assertTrue(false, "edited unchanged context remains visible")
        return
    }
    replaceText(in: afterEqualEdit,
                range: NSRange(location: NSMaxRange(editedRange), length: 0),
                with: "X",
                "first same-line unchanged context edit is accepted")
    guard let afterFirstCharacter = textViews(in: controller.view, identifier: "mergedSide").first,
          let editedXRange = nsRange(of: "edited before 1X", in: afterFirstCharacter.string) else {
        assertTrue(false, "first unchanged context character appears")
        return
    }
    replaceText(in: afterFirstCharacter,
                range: NSRange(location: NSMaxRange(editedXRange), length: 0),
                with: "Y",
                "second same-line unchanged context edit is accepted")
    guard let afterSecondCharacter = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after second unchanged context character")
        return
    }
    guard let editedXYRange = nsRange(of: "edited before 1XY", in: afterSecondCharacter.string) else {
        assertTrue(false, "top compact context edit contains both appended characters")
        return
    }
    replaceText(in: afterSecondCharacter,
                range: NSRange(location: NSMaxRange(editedXYRange), length: 0),
                with: "\n",
                "top compact context newline edit is accepted")
    layout(testWindow, controller)
    guard let afterTopNewline = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after top compact context newline")
        return
    }
    assertTrue(afterTopNewline === afterSecondCharacter,
               "top compact context newline updates in place")
    undoMergedText(in: controller, "merged text view exists for compact context newline undo")
    layout(testWindow, controller)
    guard let afterTopNewlineUndo = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after compact context newline undo")
        return
    }
    assertTrue(afterTopNewlineUndo === afterTopNewline,
               "top compact context newline undo updates in place")
    undoMergedText(in: controller, "merged text view exists for compact unchanged context undo")
    layout(testWindow, controller)
    guard let afterFirstUndo = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after first compact unchanged context undo")
        return
    }
    assertTrue(afterFirstUndo === afterSecondCharacter,
               "compact unchanged context undo updates in place")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("edited before 1X"),
               "first undo removes only the last unchanged context character")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("edited before 1XY"),
               "first undo does not keep the last unchanged context character")
    undoMergedText(in: controller, "merged text view exists for second compact unchanged context undo")
    layout(testWindow, controller)
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("edited before 1"),
               "second undo removes only the previous unchanged context character")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("edited before 1X"),
               "second undo does not jump over the previous unchanged context character")
    guard let suffixRange = nsRange(of: "before 350", in: afterFirstUndo.string) else {
        assertTrue(false, "lower visible compact context is present")
        return
    }
    replaceText(in: afterFirstUndo,
                range: suffixRange,
                with: "edited before 350",
                "lower visible compact context is editable")
    guard let afterSuffixEdit = textViews(in: controller.view, identifier: "mergedSide").first,
          let suffixEditedRange = nsRange(of: "edited before 350", in: afterSuffixEdit.string) else {
        assertTrue(false, "lower compact context edit remains visible")
        return
    }
    assertTrue(afterSuffixEdit === afterFirstUndo,
               "lower compact context edit updates in place")
    replaceText(in: afterSuffixEdit,
                range: NSRange(location: NSMaxRange(suffixEditedRange), length: 0),
                with: "X",
                "first lower compact context character edit is accepted")
    guard let afterSuffixFirstCharacter = textViews(in: controller.view, identifier: "mergedSide").first,
          let suffixEditedXRange = nsRange(of: "edited before 350X", in: afterSuffixFirstCharacter.string) else {
        assertTrue(false, "first lower compact context character appears")
        return
    }
    replaceText(in: afterSuffixFirstCharacter,
                range: NSRange(location: NSMaxRange(suffixEditedXRange), length: 0),
                with: "Y",
                "second lower compact context character edit is accepted")
    guard let afterSuffixSecondCharacter = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after lower compact context edit")
        return
    }
    undoMergedText(in: controller, "merged text view exists for lower compact context undo")
    layout(testWindow, controller)
    guard let afterSuffixFirstUndo = textViews(in: controller.view, identifier: "mergedSide").first,
          let suffixUndoRange = nsRange(of: "edited before 350X", in: afterSuffixFirstUndo.string) else {
        assertTrue(false, "lower compact context undo keeps the previous character")
        return
    }
    assertTrue(afterSuffixFirstUndo === afterSuffixSecondCharacter,
               "lower compact context undo updates in place")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("edited before 350XY"),
               "lower compact context undo removes only the last character")
    assertTrue(afterSuffixFirstUndo.selectedRange().location >= suffixUndoRange.location &&
               afterSuffixFirstUndo.selectedRange().location <= NSMaxRange(suffixUndoRange),
               "lower compact context undo keeps the selection in the lower range")
    undoMergedText(in: controller, "merged text view exists for second lower compact context undo")
    layout(testWindow, controller)
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("edited before 350"),
               "second lower compact context undo removes the previous character")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("edited before 350X"),
               "second lower compact context undo does not jump to another range")
    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↑",
                           window: testWindow,
                           "clicking top gutter control loads more context")
    layout(testWindow, controller)

    let expandedLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(expandedLines.contains("before 120"),
               "top expansion reveals 20 more context lines from the hidden middle")
    assertTrue(!expandedLines.contains("before 121"),
               "top expansion does not reveal more than 20 hidden lines")
    assertTrue(expandedLines.contains("⋯"),
               "partially expanded context keeps the remaining hidden row obvious")

    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↓",
                           window: testWindow,
                           "clicking bottom gutter control loads more context")
    layout(testWindow, controller)
    let bottomExpandedLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(bottomExpandedLines.contains("before 231"),
               "bottom expansion reveals 20 more context lines from the lower hidden side")
    assertTrue(!bottomExpandedLines.contains("before 230"),
               "bottom expansion does not reveal more than 20 hidden lines")

    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↕",
                           window: testWindow,
                           "clicking full gutter control loads all hidden context")
    layout(testWindow, controller)
    let fullyExpandedLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(fullyExpandedLines.contains("before 200"),
               "full expansion reveals all hidden context")
    assertTrue(!fullyExpandedLines.contains("⋯"),
               "full expansion removes the collapsed context band")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)
    buttons(in: controller.view).first { $0.title == "Save Merge" }?.performClick(nil)

    assertTrue(completed == true, "compact mergetool save reports completion")
    let saved = try String(contentsOf: merged, encoding: .utf8)
    var expectedBeforeLines = beforeLines
    expectedBeforeLines[0] = "edited before 1"
    expectedBeforeLines[349] = "edited before 350"
    let expected = (expectedBeforeLines + ["theirs"] + afterLines).joined(separator: "\n") + "\n"
    assertTrue(saved == expected, "compact context save preserves omitted unchanged lines")
}

func testMainWindowGitModeSavesAndStagesSelectedConflict() throws {
    let repo = try makeConflictedRepository("git-ui-conflict")

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)

    assertTrue(popUpButtons(in: controller.view).contains { $0.identifier?.rawValue == "gitConflictFilePopup" && !$0.isHidden },
               "git mode shows conflict file popup")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save and Stage" }?.isEnabled == false,
               "git save starts disabled before resolution")
    assertTrue(text(in: controller.view, identifier: "leftSide").contains("ours"), "git mode renders ours side")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("theirs"), "git mode renders theirs side")

    pickButton(in: controller.view, picksLeft: true)?.performClick(nil)
    layout(testWindow, controller)
    let save = buttons(in: controller.view).first { $0.title == "Save and Stage" }
    assertTrue(save?.isEnabled == true, "git save enables after resolution")
    save?.performClick(nil)
    layout(testWindow, controller)

    let saved = try String(contentsOf: repo.appendingPathComponent("conflict.txt"), encoding: .utf8)
    assertTrue(saved == "ours\n", "git mode writes resolved worktree file")
    let unmerged = try runGit(["ls-files", "-u"], in: repo)
    assertTrue(unmerged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "git mode stages resolved file")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save and Stage" }?.isEnabled == false,
               "resolved git file cannot be saved again immediately")
}
