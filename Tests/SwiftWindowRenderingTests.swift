import AppKit
import Foundation

func testMainWindowInitialState() {
    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)

    let titles = Set(buttons(in: controller.view).map(\.title))
    assertTrue(titles.contains("Choose Left File"), "left file button exists")
    assertTrue(titles.contains("Choose Right File"), "right file button exists")
    assertTrue(titles.contains("Compare"), "compare button exists")
    assertTrue(titles.contains("Save Result"), "save button exists")

    let compare = buttons(in: controller.view).first { $0.title == "Compare" }
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(compare?.isEnabled == false, "compare starts disabled")
    assertTrue(save?.isEnabled == false, "save starts disabled")
}

func testMainWindowIdenticalFilesEnableSaveWithoutPick() throws {
    let files = try temporaryDirectory("identical-files")
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

    let labelText = renderedText(in: controller.view)
    assertTrue(labelText.contains("alpha"), "identical files render first line")
    assertTrue(labelText.contains("beta"), "identical files render second line")
    assertTrue(labelString(in: controller.view, identifier: "leftSideLineNumbers").contains("1"), "identical files render left line numbers")
    assertTrue(labelString(in: controller.view, identifier: "mergedSideLineNumbers").isEmpty, "identical files do not render merged line numbers")
    assertTrue(labelString(in: controller.view, identifier: "rightSideLineNumbers").contains("1"), "identical files render right line numbers")
    assertTrue(text(in: controller.view, identifier: "leftSide").contains("alpha"), "identical files render left pane")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("alpha"), "identical files render merged pane")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("alpha"), "identical files render right pane")
    assertTrue(pickButtons(in: controller.view).isEmpty, "identical files have no pick buttons")

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "identical files can save immediately")
}

func testMainWindowAppliesSyntaxColorsByFileType() throws {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    let markdown = SyntaxHighlighter.attributedString(for: "# Title\n[link](target)\n",
                                                      fileName: "README.md",
                                                      font: font,
                                                      lineHeight: lineHeight)
    let cpp = SyntaxHighlighter.attributedString(for: "#include <vector>\nint main() { return 0; } // comment\n",
                                                 fileName: "main.cpp",
                                                 font: font,
                                                 lineHeight: lineHeight)
    let python = SyntaxHighlighter.attributedString(for: "def run():\n    return \"ok\"\n",
                                                    fileName: "tool.py",
                                                    font: font,
                                                    lineHeight: lineHeight)

    assertTrue(color(foregroundColor(in: markdown, matching: "# Title"), matches: .systemBlue),
               "markdown heading is syntax-colored")
    assertTrue(color(foregroundColor(in: cpp, matching: "#include"), matches: .systemBlue),
               "cpp preprocessor line is syntax-colored")
    assertTrue(color(foregroundColor(in: cpp, matching: "// comment"), matches: .systemGreen),
               "cpp comment is syntax-colored")
    assertTrue(color(foregroundColor(in: python, matching: "def"), matches: .systemPurple),
               "python keyword is syntax-colored")
    assertTrue(color(foregroundColor(in: python, matching: "\"ok\""), matches: .systemRed),
               "python string is syntax-colored")

    let files = try temporaryDirectory("syntax-colors")
    let left = files.appendingPathComponent("left.py")
    let right = files.appendingPathComponent("right.py")
    try "def run():\n    return \"left\"\n".write(to: left, atomically: true, encoding: .utf8)
    try "def run():\n    return \"right\"\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    guard let leftPane = textViews(in: controller.view, identifier: "leftSide").first else {
        assertTrue(false, "left syntax pane exists")
        return
    }
    assertTrue(color(foregroundColor(in: leftPane, matching: "def"), matches: .systemPurple),
               "loaded python pane uses python keyword color")
    assertTrue(color(foregroundColor(in: leftPane, matching: "\"left\""), matches: .systemRed),
               "loaded python pane uses python string color")
}

func testMainWindowLoadsAndPicksDiff() throws {
    let files = try temporaryDirectory("files")
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

    let labelText = renderedText(in: controller.view)
    assertTrue(labelText.contains("left"), "rendered left-side changed line")
    assertTrue(labelText.contains("right"), "rendered right-side changed line")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "leftSide"), redAtLeast: 0.8), "changed left side is red")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), greenAtLeast: 0.45), "changed right side is green")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"), "merged pane does not show an unresolved placeholder")
    assertTrue(!textLines(in: controller.view, identifier: "mergedSide").contains("left"), "merged pane starts with changed row blank")
    assertTrue(!textLines(in: controller.view, identifier: "mergedSide").contains("right"), "merged pane starts without either side picked")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "mergedSide"), redAtLeast: 0.8, greenAtLeast: 0.3), "unresolved merged pane uses fourth color")

    let useLeft = pickButton(in: controller.view, picksLeft: true)
    let useRight = pickButton(in: controller.view, picksLeft: false)
    assertTrue(useLeft?.title == "→", "left pick button points toward the middle pane")
    assertTrue(useRight != nil, "rendered Use Right button")
    assertTrue(useRight?.title == "←", "right pick button points toward the middle pane")
    assertTrue(pickButtonBaselineOffset(useLeft) < 0, "left pick arrow is optically centered in the button")
    assertTrue(pickButtonBaselineOffset(useRight) < 0, "right pick arrow is optically centered in the button")
    guard let leftPane = views(in: controller.view, identifier: "leftSide").first,
          let mergedPane = views(in: controller.view, identifier: "mergedSide").first,
          let rightPane = views(in: controller.view, identifier: "rightSide").first,
          let useLeft,
          let useRight else {
        assertTrue(false, "diff panes and arrow buttons are rendered")
        return
    }
    let leftPaneFrame = frame(of: leftPane, in: controller.view)
    let mergedPaneFrame = frame(of: mergedPane, in: controller.view)
    let rightPaneFrame = frame(of: rightPane, in: controller.view)
    let useLeftFrame = frame(of: useLeft, in: controller.view)
    let useRightFrame = frame(of: useRight, in: controller.view)
    assertTrue(useLeftFrame.midX > leftPaneFrame.maxX && useLeftFrame.midX < mergedPaneFrame.minX,
               "left arrow sits between the left and middle panes")
    assertTrue(useRightFrame.midX > mergedPaneFrame.maxX && useRightFrame.midX < rightPaneFrame.minX,
               "right arrow sits between the middle and right panes")
    guard let mergedTextViewBeforePick = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists before picking a side")
        return
    }
    useRight.performClick(nil)
    layout(testWindow, controller)

    guard let mergedTextViewAfterPick = textViews(in: controller.view, identifier: "mergedSide").first else {
        assertTrue(false, "merged text view exists after picking a side")
        return
    }
    assertTrue(mergedTextViewAfterPick === mergedTextViewBeforePick,
               "picking a side updates the merged text view in place")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "save enables after picking a changed block")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), blueAtLeast: 0.7), "picked right side is blue")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("right"), "merged pane updates to picked right content")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"), "merged pane stays placeholder-free after pick")
}

func testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane() {
    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: URL(fileURLWithPath: "Tests/diff_1"),
                    right: URL(fileURLWithPath: "Tests/diff_2"))
    layout(testWindow, controller)

    let labelText = renderedText(in: controller.view)
    assertTrue(labelText.contains("d"), "rendered deleted line from left file")
    assertTrue(labelString(in: controller.view, identifier: "leftSideLineNumbers").contains("4"), "deletion diff renders left line number gutter")
    assertTrue(labelString(in: controller.view, identifier: "mergedSideLineNumbers").isEmpty, "deletion diff does not render merged line numbers")
    assertTrue(labelString(in: controller.view, identifier: "rightSideLineNumbers").contains("4"), "deletion diff renders right line number gutter")
    assertTrue(labelString(in: controller.view, identifier: "rightSideLineNumbers")
        .components(separatedBy: "\n")
        .contains(""), "empty right-side deletion row has no line number")
    assertTrue(labels(in: controller.view).contains { !$0.frame.isEmpty && !$0.isHidden }, "rendered labels have visible frames")

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "deletion diff requires an explicit pick before saving")
    assertTrue(pickButton(in: controller.view, picksLeft: true)?.title == "→", "deletion diff renders left-to-middle arrow")
    assertTrue(pickButton(in: controller.view, picksLeft: false)?.title == "←", "deletion diff renders right-to-middle arrow")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "leftSide"), redAtLeast: 0.8), "deletion diff shows red deletion side")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), greenAtLeast: 0.45), "deletion diff shows green addition side")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"), "deletion merged pane starts without unresolved placeholder text")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)
    assertTrue(!textLines(in: controller.view, identifier: "mergedSide").contains("d"), "right pick removes deleted line from merged pane")
    assertTrue(labelString(in: controller.view, identifier: "mergedSideLineNumbers").isEmpty, "picked deletion still does not render merged line numbers")
    assertTrue(save?.isEnabled == false, "other unpicked block keeps save disabled")

    pickButton(in: controller.view, picksLeft: true)?.performClick(nil)
    layout(testWindow, controller)
    assertTrue(textLines(in: controller.view, identifier: "mergedSide").contains("d"), "left pick keeps deleted line in merged pane")
}

func testBlankSourceLinesKeepLineNumbers() throws {
    let files = try temporaryDirectory("blank-source-line-numbers")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "a\nb\nleft\n\nz\n".write(to: left, atomically: true, encoding: .utf8)
    try "a\nb\nright\n\nz\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    let expected = ["1", "2", "3", "4", "5"]
    assertTrue(labelString(in: controller.view, identifier: "leftSideLineNumbers")
        .components(separatedBy: "\n") == expected,
               "left gutter numbers real blank source lines")
    assertTrue(labelString(in: controller.view, identifier: "rightSideLineNumbers")
        .components(separatedBy: "\n") == expected,
               "right gutter numbers real blank source lines")
}

func testChangedRowsKeepStablePaneWidths() {
    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: URL(fileURLWithPath: "Tests/diff_1"),
                    right: URL(fileURLWithPath: "Tests/diff_2"))
    layout(testWindow, controller)

    assertTrue(views(in: controller.view, identifier: "diffTable").count == 1, "fixture renders one TextKit diff table")
    assertTrue(textViews(in: controller.view, identifier: "leftSide").count == 1, "left pane renders one text view")
    assertTrue(textViews(in: controller.view, identifier: "mergedSide").count == 1, "merged pane renders one text view")
    assertTrue(textViews(in: controller.view, identifier: "rightSide").count == 1, "right pane renders one text view")
    assertStableWidths(paneWidths(in: controller.view, identifier: "leftSide"), "left pane widths are stable")
    assertStableWidths(paneWidths(in: controller.view, identifier: "mergedSide"), "merged pane widths are stable")
    assertStableWidths(paneWidths(in: controller.view, identifier: "rightSide"), "right pane widths are stable")
    assertTrue(labels(in: controller.view).contains { !$0.frame.isEmpty && !$0.isHidden }, "rendered labels have visible frames")
}

func testPaneTextIsSelectableAndMergedPaneEditable() throws {
    let files = try temporaryDirectory("selectable-text")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft words\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright words\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    for identifier in ["leftSide", "rightSide"] {
        let paneTextViews = textViews(in: controller.view, identifier: identifier)
        assertTrue(paneTextViews.count == 1, "\(identifier) renders one native text view")
        assertTrue(paneTextViews.allSatisfy { !$0.isEditable }, "\(identifier) text is read-only")
        assertTrue(paneTextViews.allSatisfy { !$0.drawsBackground }, "\(identifier) text keeps pane background visible")
        assertTrue(paneTextViews.allSatisfy { $0.textContainer?.widthTracksTextView == false },
                   "\(identifier) text does not wrap")
        assertTrue(paneTextViews.allSatisfy(\.isSelectable), "\(identifier) uses native selection")
        assertTrue(views(in: controller.view, identifier: "\(identifier)SelectionOverlay").isEmpty,
                   "\(identifier) does not render custom selection overlays")
    }

    let mergedTextViews = textViews(in: controller.view, identifier: "mergedSide")
    assertTrue(mergedTextViews.count == 1, "mergedSide renders one native text view")
    assertTrue(mergedTextViews.allSatisfy(\.isEditable), "mergedSide text is editable")
    assertTrue(mergedTextViews.allSatisfy { !$0.drawsBackground }, "mergedSide text keeps pane background visible")
    assertTrue(mergedTextViews.allSatisfy { $0.textContainer?.widthTracksTextView == false },
               "mergedSide text does not wrap")
    assertTrue(mergedTextViews.allSatisfy(\.isSelectable), "mergedSide uses native selection")
    assertTrue(views(in: controller.view, identifier: "mergedSideSelectionOverlay").isEmpty,
               "mergedSide does not render custom selection overlays")

    assertTrue(text(in: controller.view, identifier: "leftSide").contains("left words"),
               "left pane text remains discoverable")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("right words"),
               "right pane text remains discoverable")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"),
               "merged pane does not render unresolved placeholder text")
}

func testMergedPaneTextBecomesSelectableAfterPick() throws {
    let files = try temporaryDirectory("picked-merged-selectable")
    let left = files.appendingPathComponent("left.txt")
    let right = files.appendingPathComponent("right.txt")
    try "alpha\nleft words\nomega\n".write(to: left, atomically: true, encoding: .utf8)
    try "alpha\nright words\nomega\n".write(to: right, atomically: true, encoding: .utf8)

    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: left, right: right)
    layout(testWindow, controller)

    let unpicked = textViews(in: controller.view, identifier: "mergedSide").first
    assertTrue(unpicked?.string.contains("Unresolved") == false, "unpicked merged pane has no placeholder text")
    assertTrue(unpicked?.isSelectable == true, "merged pane uses native selection before pick")
    assertTrue(unpicked?.isEditable == true, "merged pane is editable before pick")

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)

    let picked = textViews(in: controller.view, identifier: "mergedSide").first
    assertTrue(picked?.string.contains("right words") == true, "picked merged text appears in the native text view")
    assertTrue(picked?.string.contains("Unresolved") == false, "picked merged text remains placeholder-free")
    assertTrue(picked?.isSelectable == true, "picked merged text remains selectable")
    assertTrue(picked?.isEditable == true, "picked merged text remains editable")
}

func testSidePickUndoRedoRestoresMergedState() throws {
    let files = try temporaryDirectory("pick-undo-redo")
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

    pickButton(in: controller.view, picksLeft: false)?.performClick(nil)
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("right"),
               "right pick appears before undo")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == true,
               "right pick enables save before undo")

    undoMergedText(in: controller, "merged text view exists for pick undo")
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["alpha", "", "omega"],
               "undoing a pick restores the unpicked blank changed row")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == false,
               "undoing a pick disables save again")

    redoMergedText(in: controller, "merged text view exists for pick redo")
    layout(testWindow, controller)

    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("right"),
               "redoing a pick restores picked text")
    assertTrue(buttons(in: controller.view).first { $0.title == "Save Result" }?.isEnabled == true,
               "redoing a pick re-enables save")
}
