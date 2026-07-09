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
    if let leftGutter = views(in: controller.view, identifier: "leftSideLineNumbers").first as? PaneLineNumberView {
        let pillRect = NSRect(x: 0,
                              y: 0,
                              width: leftGutter.bounds.width,
                              height: controller.lineHeight).insetBy(dx: 5, dy: 2)
        for symbol in ["↑", "↕", "↓"] {
            let symbolRect = leftGutter.controlSymbolDrawRect(symbol: symbol, in: pillRect)
            assertTrue(abs(symbolRect.midX - pillRect.midX) <= 0.5,
                       "\(symbol) compact context control is horizontally centered")
            assertTrue(abs(symbolRect.midY - pillRect.midY) <= 0.5,
                       "\(symbol) compact context control is vertically centered")
        }
    } else {
        assertTrue(false, "line number gutter uses the custom control renderer")
    }
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
    guard let beforeExpansion = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists before compact context expansion")
        return
    }
    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↑",
                           window: testWindow,
                           "clicking top gutter control loads more context")
    layout(testWindow, controller)
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").first === beforeExpansion,
               "top context expansion updates in place")

    let expandedLines = textLines(in: controller.view, identifier: "mergedSide")
    let expandedPrefixLimit = controller.gitContextLineCount + controller.gitContextExpansionLineCount
    assertTrue(expandedLines.contains("before \(expandedPrefixLimit)"),
               "top expansion reveals the configured number of context lines from the hidden middle")
    assertTrue(!expandedLines.contains("before \(expandedPrefixLimit + 1)"),
               "top expansion does not reveal more than the configured number of hidden lines")
    assertTrue(expandedLines.contains("⋯"),
               "partially expanded context keeps the remaining hidden row obvious")

    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↓",
                           window: testWindow,
                           "clicking bottom gutter control loads more context")
    layout(testWindow, controller)
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").first === beforeExpansion,
               "bottom context expansion updates in place")
    let bottomExpandedLines = textLines(in: controller.view, identifier: "mergedSide")
    let expandedSuffixStart = beforeLines.count - expandedPrefixLimit + 1
    assertTrue(bottomExpandedLines.contains("before \(expandedSuffixStart)"),
               "bottom expansion reveals the configured number of context lines from the lower hidden side")
    assertTrue(!bottomExpandedLines.contains("before \(expandedSuffixStart - 1)"),
               "bottom expansion does not reveal more than the configured number of hidden lines")

    clickLineNumberControl(in: controller.view,
                           identifier: "leftSideLineNumbers",
                           symbol: "↕",
                           window: testWindow,
                           "clicking full gutter control loads all hidden context")
    layout(testWindow, controller)
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").first === beforeExpansion,
               "full context expansion updates in place")
    let fullyExpandedLines = textLines(in: controller.view, identifier: "mergedSide")
    assertTrue(fullyExpandedLines.contains("before 200"),
               "full expansion reveals all hidden context")
    assertTrue(!fullyExpandedLines.contains("⋯"),
               "full expansion removes the collapsed context band")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").first === beforeExpansion,
               "picking a side after expansion updates in place")
    buttons(in: controller.view).first { $0.title == "Save Merge" }?.performClick(nil)

    assertTrue(completed == true, "compact mergetool save reports completion")
    let saved = try String(contentsOf: merged, encoding: .utf8)
    var expectedBeforeLines = beforeLines
    expectedBeforeLines[0] = "edited before 1"
    expectedBeforeLines[349] = "edited before 350"
    let expected = (expectedBeforeLines + ["theirs"] + afterLines).joined(separator: "\n") + "\n"
    assertTrue(saved == expected, "compact context save preserves omitted unchanged lines")
}

func testRepeatedNewlineInCompactSuffixKeepsCaretAtLineStart() throws {
    let files = try temporaryDirectory("git-mergetool-compact-suffix-caret")
    let base = files.appendingPathComponent("base.txt")
    let local = files.appendingPathComponent("local.txt")
    let remote = files.appendingPathComponent("remote.txt")
    let merged = files.appendingPathComponent("merged.txt")
    try "base\n".write(to: base, atomically: true, encoding: .utf8)
    try "ours\n".write(to: local, atomically: true, encoding: .utf8)
    try "theirs\n".write(to: remote, atomically: true, encoding: .utf8)

    let beforeLines = (1...350).map { "before \($0)" }
    let conflicted = (beforeLines + [
        "<<<<<<< HEAD",
        "ours",
        "=======",
        "theirs",
        ">>>>>>> branch"
    ]).joined(separator: "\n") + "\n"
    try conflicted.write(to: merged, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGitMergeTool(base: base, local: local, remote: remote, merged: merged)
    layout(testWindow, controller)

    guard let initialMerged = textViews(in: controller.view, identifier: "mergedSide").first,
          let suffixRange = nsRange(of: "before 325", in: initialMerged.string) else {
        assertTrue(false, "compact suffix line before the diff is visible")
        return
    }

    var textView = initialMerged
    var insertion = NSRange(location: NSMaxRange(suffixRange), length: 0)
    for index in 1...3 {
        replaceText(in: textView,
                    range: insertion,
                    with: "\n",
                    "compact suffix accepts repeated newline \(index)")
        layout(testWindow, controller)
        guard let afterEdit = textViews(in: controller.view, identifier: "mergedSide").first else {
            assertTrue(false, "merged text view exists after compact suffix newline \(index)")
            return
        }
        assertTrue(afterEdit === initialMerged,
                   "compact suffix newline \(index) updates in place")
        assertTrue(selectionIsAtLineStart(afterEdit),
                   "compact suffix newline \(index) keeps the caret at the next line start")
        textView = afterEdit
        insertion = afterEdit.selectedRange()
    }
}

func testMainWindowGitModeSavesAndStagesSelectedConflict() throws {
    let repo = try makeConflictedRepository("git-ui-conflict")
    try "review me\n".write(to: repo.appendingPathComponent("review.txt"), atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)

    guard let outline = gitFileOutline(in: controller) else {
        assertTrue(false, "git mode shows file browser")
        return
    }
    assertTrue(views(in: controller.view, identifier: "gitFileBrowser").first?.isHidden == false,
               "git mode shows file browser")
    assertTrue(gitFileBrowserTitles(in: outline) == ["Needs Resolution", "Review Changes"],
               "git mode starts with two folder rows")
    expandGitFileBrowserFolder("Needs Resolution", in: controller)
    expandGitFileBrowserFolder("Review Changes", in: controller)
    let browserTitles = gitFileBrowserTitles(in: outline)
    assertTrue(browserTitles.contains("conflict.txt"), "git mode lists conflict file inside folder")
    assertTrue(browserTitles.contains("review.txt (untracked)"), "git mode lists ordinary changed file inside folder")
    assertTrue(textViews(in: controller.view, identifier: "leftSide").isEmpty,
               "git mode waits for a file selection before rendering")

    selectGitFile("conflict.txt", in: controller)
    layout(testWindow, controller)

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
    if let outline = gitFileOutline(in: controller) {
        guard let needsResolution = gitFileBrowserNode(titled: "Needs Resolution", in: outline),
              let reviewChanges = gitFileBrowserNode(titled: "Review Changes", in: outline) else {
            assertTrue(false, "git file browser keeps both folders after save")
            return
        }
        let needsResolutionTitles = needsResolution.children.map(\.title)
        let reviewChangesTitles = reviewChanges.children.map(\.title)
        assertTrue(!needsResolutionTitles.contains("conflict.txt (saved)"),
                   "saved conflict leaves needs resolution folder")
        assertTrue(reviewChangesTitles.contains("conflict.txt (saved)"),
                   "saved conflict moves to review changes folder")
    } else {
        assertTrue(false, "git file browser exists after save")
    }
}

func testGitFileBrowserSidebarToggleHidesSidebarAndResizeHandleChangesWidth() throws {
    let repo = try makeConflictedRepository("git-ui-file-browser-size")

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)
    selectGitFile("conflict.txt", in: controller)
    layout(testWindow, controller)

    guard let browserColumn = views(in: controller.view, identifier: "gitFileBrowserColumn").first,
          let browser = views(in: controller.view, identifier: "gitFileBrowser").first,
          let searchField = gitFileSearchField(in: controller),
          let toggleButton = buttons(in: controller.view).first(where: { $0.identifier?.rawValue == "gitFileBrowserToggleButton" }),
          let resizeHandle = views(in: controller.view, identifier: "gitFileBrowserResizeHandle").first else {
        assertTrue(false, "git mode exposes file browser controls")
        return
    }

    assertTrue(browserColumn.isHidden == false, "git mode shows file browser column")
    assertTrue(browser.isHidden == false, "git mode shows file browser")
    assertTrue(resizeHandle.isHidden == false, "git mode shows file browser resize handle")
    assertTrue(toggleButton.isHidden == false, "git mode shows stable file browser toggle")
    assertTrue(controller.gitFileBrowserColumn.arrangedSubviews.first === controller.gitFileBrowserToggleRow,
               "file browser toggle row sits above the search bar")
    assertTrue(controller.gitFileBrowserToggleRow.arrangedSubviews.first === toggleButton,
               "file browser toggle is the leftmost control in the sidebar")
    let columnRows = controller.gitFileBrowserColumn.arrangedSubviews
    let toggleRowIndex = columnRows.firstIndex(of: controller.gitFileBrowserToggleRow) ?? -1
    let browserPanelIndex = columnRows.firstIndex(of: controller.gitFileBrowserPanel) ?? -1
    assertTrue(toggleRowIndex >= 0 && toggleRowIndex < browserPanelIndex,
               "file browser content appears below the toggle row")
    assertTrue(controller.gitFileBrowserPanel.arrangedSubviews.first === searchField,
               "file browser search appears directly below the toggle row")
    let initialBrowserWidth = frame(of: browser, in: controller.view).width
    let initialPaneWidth = paneWidths(in: controller.view, identifier: "leftSide").first ?? 0

    controller.resizeGitFileBrowser(to: 180)
    layout(testWindow, controller)

    let resizedBrowserWidth = frame(of: browser, in: controller.view).width
    let resizedPaneWidth = paneWidths(in: controller.view, identifier: "leftSide").first ?? 0
    assertTrue(browser.isHidden == false, "resizing keeps file browser visible")
    assertTrue(resizedBrowserWidth < initialBrowserWidth - 50,
               "resize handle can narrow file browser")
    assertTrue(resizedPaneWidth > initialPaneWidth + 20,
               "narrowing the file browser gives diff panes more room")

    let toggleFrameBeforeHide = frame(of: toggleButton, in: controller.view)
    toggleButton.performClick(nil)
    layout(testWindow, controller)

    let hiddenPaneWidth = paneWidths(in: controller.view, identifier: "leftSide").first ?? 0
    let toggleFrameAfterHide = frame(of: toggleButton, in: controller.view)
    assertTrue(browserColumn.isHidden == false, "sidebar toggle column stays visible after hiding the file browser")
    assertTrue(browser.isHidden, "sidebar toggle removes file browser content")
    assertTrue(resizeHandle.isHidden, "sidebar toggle removes resize handle")
    assertTrue(toggleButton.isHidden == false, "sidebar toggle stays visible after hiding the file browser")
    assertTrue(abs(toggleFrameBeforeHide.midY - toggleFrameAfterHide.midY) < 2
               && abs(toggleFrameBeforeHide.minX - toggleFrameAfterHide.minX) < 2,
               "sidebar toggle does not move when clicked")
    assertTrue(hiddenPaneWidth > resizedPaneWidth + 20,
               "hiding the file browser gives diff panes the most room")

    toggleButton.performClick(nil)
    layout(testWindow, controller)

    assertTrue(browser.isHidden == false, "sidebar toggle restores file browser")
    assertTrue(resizeHandle.isHidden == false, "sidebar toggle restores resize handle")
    assertTrue(abs(frame(of: browser, in: controller.view).width - resizedBrowserWidth) < 2,
               "restore keeps the user's resized file browser width")
}

func testMainWindowGitModeStagesMarkerlessUnmergedFile() throws {
    let repo = try makeMarkerlessUnmergedRepository("git-ui-markerless")
    let relativePath = "markerless.txt"

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)

    let worktreeText = try String(contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
    assertTrue(!worktreeText.contains("<<<<<<<"), "markerless unmerged fixture has no conflict markers")
    let unmergedBefore = try runGit(["ls-files", "-u", "--", relativePath], in: repo)
    assertTrue(!unmergedBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "markerless fixture starts unmerged")

    guard let fileIndex = controller.gitConflictFiles.firstIndex(where: { ($0.relativePath ?? "") == relativePath }) else {
        assertTrue(false, "git mode lists markerless unmerged file")
        return
    }
    let file = controller.gitConflictFiles[fileIndex]
    assertTrue(file.isConflict, "markerless unmerged file is still a git conflict")

    let alert = controller.markerlessConflictAlert(relativePath: relativePath)
    assertTrue(alert.messageText == controller.markerlessConflictMessage,
               "markerless conflict alert uses the requested message")
    assertTrue(alert.buttons.map(\.title) == ["Add to Git", "Cancel"],
               "markerless conflict alert offers Add to Git")

    controller.selectedGitConflictIndex = fileIndex
    assertTrue(controller.stageMarkerlessGitConflict(file: file),
               "markerless unmerged file can be added to git")

    let unmergedAfter = try runGit(["ls-files", "-u", "--", relativePath], in: repo)
    assertTrue(unmergedAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "adding markerless unmerged file clears unmerged index entries")
    guard let needsResolution = controller.gitFileBrowserNodes.first(where: { $0.title == "Needs Resolution" }),
          let reviewChanges = controller.gitFileBrowserNodes.first(where: { $0.title == "Review Changes" }) else {
        assertTrue(false, "git file browser keeps both folders after adding markerless conflict")
        return
    }
    assertTrue(!needsResolution.children.map(\.title).contains("\(relativePath) (saved)"),
               "added markerless file leaves needs resolution folder")
    assertTrue(reviewChanges.children.map(\.title).contains("\(relativePath) (saved)"),
               "added markerless file moves to review changes folder")
}

func testMainWindowGitFileBrowserSearchFiltersFolders() throws {
    let repo = try makeConflictedRepository("git-ui-search")
    try "review me\n".write(to: repo.appendingPathComponent("review.txt"), atomically: true, encoding: .utf8)
    let docs = repo.appendingPathComponent("docs", isDirectory: true)
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    try "notes\n".write(to: docs.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)

    guard let outline = gitFileOutline(in: controller),
          let searchField = gitFileSearchField(in: controller) else {
        assertTrue(false, "git mode shows file browser and search")
        return
    }
    assertTrue(searchField.isHidden == false, "git file search is visible in git mode")

    searchGitFiles("review", in: controller)
    layout(testWindow, controller)
    guard let needsResolution = gitFileBrowserNode(titled: "Needs Resolution", in: outline),
          let reviewChanges = gitFileBrowserNode(titled: "Review Changes", in: outline) else {
        assertTrue(false, "git file browser keeps both folders while searching")
        return
    }
    assertTrue(needsResolution.children.map(\.title) == ["No matches"],
               "search shows no matches in empty conflict folder")
    assertTrue(reviewChanges.children.map(\.title) == ["review.txt (untracked)"],
               "search filters review changes by file name")
    assertTrue(textViews(in: controller.view, identifier: "leftSide").isEmpty,
               "searching files does not open a file")

    searchGitFiles("conflict", in: controller)
    layout(testWindow, controller)
    guard let filteredNeedsResolution = gitFileBrowserNode(titled: "Needs Resolution", in: outline),
          let filteredReviewChanges = gitFileBrowserNode(titled: "Review Changes", in: outline) else {
        assertTrue(false, "git file browser keeps both folders after changing search")
        return
    }
    assertTrue(filteredNeedsResolution.children.map(\.title) == ["conflict.txt"],
               "search filters needs resolution by file name")
    assertTrue(filteredReviewChanges.children.map(\.title) == ["No matches"],
               "search hides unrelated review changes")

    searchGitFiles("", in: controller)
    layout(testWindow, controller)
    guard let restoredNeedsResolution = gitFileBrowserNode(titled: "Needs Resolution", in: outline),
          let restoredReviewChanges = gitFileBrowserNode(titled: "Review Changes", in: outline) else {
        assertTrue(false, "git file browser keeps both folders after clearing search")
        return
    }
    assertTrue(restoredNeedsResolution.children.map(\.title) == ["conflict.txt"],
               "clearing search restores conflict files")
    assertTrue(restoredReviewChanges.children.map(\.title).contains("review.txt (untracked)")
               && restoredReviewChanges.children.map(\.title).contains("docs/notes.md (untracked)"),
               "clearing search restores review files")
}

func testMainWindowGitModeShowsOrdinaryModifiedDiff() throws {
    let repo = try temporaryDirectory("git-ui-modified-diff")
    try runGit(["init"], in: repo)
    try runGit(["config", "user.email", "mcdiff-tests@example.com"], in: repo)
    try runGit(["config", "user.name", "MacDiff Tests"], in: repo)

    let file = repo.appendingPathComponent("changed.txt")
    try "before\nsame\n".write(to: file, atomically: true, encoding: .utf8)
    try runGit(["add", "changed.txt"], in: repo)
    try runGit(["commit", "-m", "base"], in: repo)
    try "after\nsame\n".write(to: file, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)

    guard let outline = gitFileOutline(in: controller) else {
        assertTrue(false, "git mode shows file browser")
        return
    }
    assertTrue(views(in: controller.view, identifier: "gitFileBrowser").first?.isHidden == false,
               "git mode shows file browser")
    expandGitFileBrowserFolder("Review Changes", in: controller)
    assertTrue(gitFileBrowserTitles(in: outline).contains("changed.txt (modified)"),
               "git mode lists ordinary modified file")

    selectGitFile("changed.txt (modified)", in: controller)
    layout(testWindow, controller)

    assertTrue(buttons(in: controller.view).first { $0.title == "Diff Only" }?.isEnabled == false,
               "ordinary git diff is read-only")
    assertTrue(text(in: controller.view, identifier: "leftSide").contains("before"),
               "git diff renders HEAD side")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("after"),
               "git diff renders worktree side")
    assertTrue(pickButtons(in: controller.view).isEmpty,
               "ordinary git diff does not render merge pick buttons")
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").isEmpty,
               "ordinary git diff does not render a merged pane")
    assertTrue(stackViews(in: controller.view, identifier: "diffTable").first?.arrangedSubviews.count == 2,
               "ordinary git diff renders only before and after panes")
}

func testMainWindowGitModeCompactsOrdinaryModifiedDiffContext() throws {
    let repo = try temporaryDirectory("git-ui-modified-diff-context")
    try runGit(["init"], in: repo)
    try runGit(["config", "user.email", "mcdiff-tests@example.com"], in: repo)
    try runGit(["config", "user.name", "MacDiff Tests"], in: repo)

    let beforeContext = (1...60).map { "before-\($0)" }
    let afterContext = (1...60).map { "after-\($0)" }
    let file = repo.appendingPathComponent("changed.txt")
    try (beforeContext + ["old"] + afterContext).joined(separator: "\n")
        .appending("\n")
        .write(to: file, atomically: true, encoding: .utf8)
    try runGit(["add", "changed.txt"], in: repo)
    try runGit(["commit", "-m", "base"], in: repo)
    try (beforeContext + ["new"] + afterContext).joined(separator: "\n")
        .appending("\n")
        .write(to: file, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.loadGit(startPath: repo)
    layout(testWindow, controller)
    selectGitFile("changed.txt (modified)", in: controller)
    layout(testWindow, controller)

    let leftLines = textLines(in: controller.view, identifier: "leftSide")
    let rightLines = textLines(in: controller.view, identifier: "rightSide")
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").isEmpty,
               "compacted ordinary git diff stays two-pane")
    assertTrue(leftLines.contains("⋯") && rightLines.contains("⋯"),
               "ordinary git diff shows collapsed context controls")
    assertTrue(leftLines.contains("before-1") && leftLines.contains("before-60"),
               "ordinary git diff keeps edge context before the change")
    assertTrue(leftLines.contains("after-1") && leftLines.contains("after-60"),
               "ordinary git diff keeps edge context after the change")
    assertTrue(!leftLines.contains("before-30") && !rightLines.contains("after-30"),
               "ordinary git diff omits middle unchanged context")
    assertTrue(leftLines.count < 121 && rightLines.count < 121,
               "ordinary git diff renders fewer rows than the full file")
}
