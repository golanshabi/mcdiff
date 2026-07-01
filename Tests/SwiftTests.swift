import AppKit
import Foundation

private var testLogDirectory: URL?

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Swift test failed: \(message)\n", stderr)
        exit(1)
    }
}

private func temporaryDirectory(_ name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mcdiff-swift-tests-\(getpid())-\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func allSubviews(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

private func buttons(in view: NSView) -> [NSButton] {
    allSubviews(of: view).compactMap { $0 as? NSButton }
}

private func sliders(in view: NSView) -> [NSSlider] {
    allSubviews(of: view).compactMap { $0 as? NSSlider }
}

private func labels(in view: NSView) -> [NSTextField] {
    allSubviews(of: view).compactMap { $0 as? NSTextField }
}

private func textViews(in view: NSView) -> [NSTextView] {
    allSubviews(of: view).compactMap { $0 as? NSTextView }
}

private func views(in view: NSView, identifier: String) -> [NSView] {
    allSubviews(of: view).filter { $0.identifier?.rawValue == identifier }
}

private func labels(in view: NSView, identifier: String) -> [NSTextField] {
    views(in: view, identifier: identifier).flatMap { matchedView in
        allSubviews(of: matchedView).compactMap { $0 as? NSTextField }
    }
}

private func textViews(in view: NSView, identifier: String) -> [NSTextView] {
    views(in: view, identifier: identifier).flatMap { matchedView in
        allSubviews(of: matchedView).compactMap { $0 as? NSTextView }
    }
}

private func text(in view: NSView, identifier: String) -> String {
    let selectableText = textViews(in: view, identifier: identifier)
    if !selectableText.isEmpty {
        return selectableText.map(\.string).joined(separator: "\n")
    }

    return labels(in: view, identifier: identifier).map(\.stringValue).joined(separator: "\n")
}

private func renderedText(in view: NSView) -> String {
    (labels(in: view).map(\.stringValue) + textViews(in: view).map(\.string)).joined(separator: "\n")
}

private func labelString(in view: NSView, identifier: String) -> String {
    labels(in: view)
        .filter { $0.identifier?.rawValue == identifier }
        .map(\.stringValue)
        .joined(separator: "\n")
}

private func labelStrings(in view: NSView, identifier: String) -> [String] {
    labels(in: view)
        .filter { $0.identifier?.rawValue == identifier }
        .map(\.stringValue)
}

private func textLines(in view: NSView, identifier: String) -> [String] {
    text(in: view, identifier: identifier)
        .components(separatedBy: "\n")
}

private func stackViews(in view: NSView) -> [NSStackView] {
    allSubviews(of: view).compactMap { $0 as? NSStackView }
}

private func stackViews(in view: NSView, identifier: String) -> [NSStackView] {
    stackViews(in: view).filter { $0.identifier?.rawValue == identifier }
}

private func horizontalControl(in view: NSView, identifier: String) -> NSSlider? {
    sliders(in: view).first { $0.identifier?.rawValue == identifier }
}

private func scrollView(in view: NSView, identifier: String) -> NSScrollView? {
    allSubviews(of: view)
        .compactMap { $0 as? NSScrollView }
        .first { $0.identifier?.rawValue == identifier }
}

private func sendSliderAction(_ slider: NSSlider) {
    guard let action = slider.action else {
        assertTrue(false, "slider has an action")
        return
    }
    _ = slider.sendAction(action, to: slider.target)
}

private func textLabelOrigins(in view: NSView, clipIdentifier: String) -> [CGFloat] {
    views(in: view, identifier: clipIdentifier).compactMap { clip in
        allSubviews(of: clip).compactMap { ($0 as? NSTextView)?.frame.origin.x }.first
    }
}

private func paneWidths(in view: NSView, identifier: String) -> [CGFloat] {
    views(in: view, identifier: identifier).map(\.frame.width)
}

private func assertStableWidths(_ widths: [CGFloat], _ message: String) {
    guard let first = widths.first else {
        assertTrue(false, "\(message) has widths")
        return
    }
    for width in widths {
        assertTrue(abs(width - first) < 1.0, message)
    }
}

private func window(for controller: MainWindowController) -> NSWindow {
    NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
             styleMask: [.titled, .closable, .miniaturizable, .resizable],
             backing: .buffered,
             defer: false)
}

private func layout(_ window: NSWindow, _ controller: MainWindowController) {
    window.contentViewController = controller
    window.layoutIfNeeded()
    controller.view.layoutSubtreeIfNeeded()
}

private func colorComponents(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
}

private func backgroundColors(in view: NSView) -> [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)] {
    stackViews(in: view).compactMap { stack in
        guard let cgColor = stack.layer?.backgroundColor else { return nil }
        return colorComponents(NSColor(cgColor: cgColor) ?? .clear)
    }
}

private func backgroundColors(in view: NSView,
                              identifier: String) -> [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)] {
    let stackColors: [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)] = stackViews(in: view, identifier: identifier).compactMap { stack in
        guard let cgColor = stack.layer?.backgroundColor else { return nil }
        return colorComponents(NSColor(cgColor: cgColor) ?? .clear)
    }
    let paneColors = views(in: view, identifier: identifier)
        .compactMap { $0 as? PaneColumnView }
        .flatMap { pane in pane.backgroundRuns.map { colorComponents($0.color) } }
    return stackColors + paneColors
}

private func hasColor(_ colors: [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)],
                      redAtLeast minRed: CGFloat = 0,
                      greenAtLeast minGreen: CGFloat = 0,
                      blueAtLeast minBlue: CGFloat = 0,
                      alphaAtLeast minAlpha: CGFloat = 0.01) -> Bool {
    colors.contains { color in
        color.red >= minRed && color.green >= minGreen && color.blue >= minBlue && color.alpha >= minAlpha
    }
}

private func testLoggerCreatesRunFolderAndPrunesOldRuns() throws {
    let baseDirectory = try temporaryDirectory("logs")
    AppLoggerIsTesting = true
    AppLoggerTestingBaseDirectory = baseDirectory

    let manager = FileManager.default
    for index in 0..<12 {
        let runDirectory = baseDirectory.appendingPathComponent("old-\(index)", isDirectory: true)
        try manager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: TimeInterval(index))
        try manager.setAttributes([.modificationDate: date], ofItemAtPath: runDirectory.path)
    }

    AppLogger.initialize()
    AppLogger.info("swift logger test")

    let runDirectories = try manager.contentsOfDirectory(
        at: baseDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ).filter { url in
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    assertTrue(runDirectories.count == 10, "logger keeps exactly 10 run folders")
    let currentRun = runDirectories.first { $0.lastPathComponent.hasSuffix("_\(getpid())") }
    assertTrue(currentRun != nil, "logger creates a current run folder with PID suffix")
    assertTrue(currentRun!.lastPathComponent.range(
        of: #"^\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2}_\d+$"#,
        options: .regularExpression
    ) != nil, "logger run folder is date-first and PID-last")
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("swift.log").path), "swift.log exists")
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("cpp.log").path), "cpp.log exists")

    let swiftLog = try String(contentsOf: currentRun!.appendingPathComponent("swift.log"), encoding: .utf8)
    assertTrue(swiftLog.contains("swift logger test"), "swift.log contains written message")

    testLogDirectory = currentRun
    MDSetLogDirectory(currentRun!.path)
}

private func testBridgeDiffMergeAndErrors() throws {
    var error: NSError?
    guard let document = MDMakeDiff("one\nleft\nthree\n",
                                    "one\nright\nthree\n",
                                    &error) else {
        assertTrue(false, "bridge returns document")
        return
    }

    assertTrue(error == nil, "bridge diff has no error")
    assertTrue(document.blocks.count == 3, "bridge document has expected block count")
    assertTrue(document.canSave() == false, "bridge document cannot save before pick")

    do {
        _ = try document.mergedText()
        assertTrue(false, "bridge merge throws before pick")
    } catch {
        assertTrue(error.localizedDescription.contains("Choose a side"), "bridge merge reports pick error")
    }

    let changedBlock = document.blocks[1]
    changedBlock.pick = .right
    assertTrue(document.canSave(), "bridge document can save after pick")

    let merged = try document.mergedText()
    assertTrue(merged == "one\nright\nthree\n", "bridge merge after pick output")

    guard let testLogDirectory else {
        assertTrue(false, "test log directory is available")
        return
    }
    let cppLog = try String(contentsOf: testLogDirectory.appendingPathComponent("cpp.log"), encoding: .utf8)
    assertTrue(cppLog.contains("Bridge requested diff"), "cpp.log contains bridge diff message")
    assertTrue(cppLog.contains("Merged text bytes"), "cpp.log contains merge message")
}

private func testMainWindowInitialState() {
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

private func testMainWindowIdenticalFilesEnableSaveWithoutPick() throws {
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
    assertTrue(buttons(in: controller.view).contains { $0.title == "Use Left" } == false, "identical files have no pick buttons")

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "identical files can save immediately")
}

private func testMainWindowLoadsAndPicksDiff() throws {
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

    let useRight = buttons(in: controller.view).first { $0.title == "Use Right" }
    assertTrue(useRight != nil, "rendered Use Right button")
    useRight?.performClick(nil)
    layout(testWindow, controller)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "save enables after picking a changed block")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), blueAtLeast: 0.7), "picked right side is blue")
    assertTrue(text(in: controller.view, identifier: "mergedSide").contains("right"), "merged pane updates to picked right content")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"), "merged pane stays placeholder-free after pick")
}

private func testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane() {
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
    assertTrue(buttons(in: controller.view).contains { $0.title == "Use Left" }, "deletion diff renders Use Left")
    assertTrue(buttons(in: controller.view).contains { $0.title == "Use Right" }, "deletion diff renders Use Right")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "leftSide"), redAtLeast: 0.8), "deletion diff shows red deletion side")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), greenAtLeast: 0.45), "deletion diff shows green addition side")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"), "deletion merged pane starts without unresolved placeholder text")

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)
    assertTrue(!textLines(in: controller.view, identifier: "mergedSide").contains("d"), "right pick removes deleted line from merged pane")
    assertTrue(labelString(in: controller.view, identifier: "mergedSideLineNumbers").isEmpty, "picked deletion still does not render merged line numbers")
    assertTrue(save?.isEnabled == false, "other unpicked block keeps save disabled")

    buttons(in: controller.view).first { $0.title == "Use Left" }?.performClick(nil)
    layout(testWindow, controller)
    assertTrue(textLines(in: controller.view, identifier: "mergedSide").contains("d"), "left pick keeps deleted line in merged pane")
}

private func testChangedRowsKeepStablePaneWidths() {
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

private func testPaneTextIsSelectableAndReadOnly() throws {
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

    for identifier in ["leftSide", "mergedSide", "rightSide"] {
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

    assertTrue(text(in: controller.view, identifier: "leftSide").contains("left words"),
               "left pane text remains discoverable")
    assertTrue(text(in: controller.view, identifier: "rightSide").contains("right words"),
               "right pane text remains discoverable")
    assertTrue(!text(in: controller.view, identifier: "mergedSide").contains("Unresolved"),
               "merged pane does not render unresolved placeholder text")
}

private func testMergedPaneTextBecomesSelectableAfterPick() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)

    let picked = textViews(in: controller.view, identifier: "mergedSide").first
    assertTrue(picked?.string.contains("right words") == true, "picked merged text appears in the native text view")
    assertTrue(picked?.string.contains("Unresolved") == false, "picked merged text remains placeholder-free")
    assertTrue(picked?.isSelectable == true, "picked merged text remains selectable")
}

private func testPaneUsesOneNativeSelectionAcrossMultipleTextBlocks() throws {
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

private func testNativeTextSelectionKeepsPartialWordRange() throws {
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

private func testPickingOneBlockLeavesOtherMergedBlocksBlankAndUnsaved() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)

    let mergedText = text(in: controller.view, identifier: "mergedSide")
    assertTrue(mergedText.contains("right1"), "first picked block updates merged pane")
    assertTrue(!mergedText.contains("left1"), "first picked block no longer shows old text in merged pane")
    assertTrue(textLines(in: controller.view, identifier: "mergedSide").contains(""), "second unpicked block remains blank")
    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "second unpicked block keeps save disabled")
}

private func testPickingSmallerConflictSqueezesMergedRows() throws {
    let files = try temporaryDirectory("smaller-pick-squeezes")
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)

    assertTrue(textLines(in: controller.view, identifier: "mergedSide") == ["same", "right one", "tail"],
               "picking the smaller side removes the extra merged rows")
    assertTrue(textLines(in: controller.view, identifier: "leftSide").count == 3,
               "all panes squeeze to the picked merged row count")
    assertTrue(textLines(in: controller.view, identifier: "rightSide").count == 3,
               "right pane stays aligned after the squeeze")
}

private func testLongLineSlidersMoveAllPanesTogetherWithoutChangingPaneWidths() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Left" }?.performClick(nil)
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

@main
private enum SwiftTests {
    static func main() {
        do {
            try testLoggerCreatesRunFolderAndPrunesOldRuns()
            try testBridgeDiffMergeAndErrors()
            testMainWindowInitialState()
            try testMainWindowIdenticalFilesEnableSaveWithoutPick()
            try testMainWindowLoadsAndPicksDiff()
            testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane()
            testChangedRowsKeepStablePaneWidths()
            try testPaneTextIsSelectableAndReadOnly()
            try testMergedPaneTextBecomesSelectableAfterPick()
            try testPaneUsesOneNativeSelectionAcrossMultipleTextBlocks()
            try testNativeTextSelectionKeepsPartialWordRange()
            try testPickingOneBlockLeavesOtherMergedBlocksBlankAndUnsaved()
            try testPickingSmallerConflictSqueezesMergedRows()
            try testLongLineSlidersMoveAllPanesTogetherWithoutChangingPaneWidths()
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
