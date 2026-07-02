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

private func popUpButtons(in view: NSView) -> [NSPopUpButton] {
    allSubviews(of: view).compactMap { $0 as? NSPopUpButton }
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

@discardableResult
private func runGit(_ arguments: [String],
                    in directory: URL,
                    allowFailure: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    if process.terminationStatus != 0 && !allowFailure {
        throw NSError(domain: "SwiftTests", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(text)"
        ])
    }
    return text
}

private func makeConflictedRepository(_ name: String) throws -> URL {
    let repo = try temporaryDirectory(name)
    try runGit(["init"], in: repo)
    try runGit(["config", "user.email", "mcdiff-tests@example.com"], in: repo)
    try runGit(["config", "user.name", "MacDiff Tests"], in: repo)

    let file = repo.appendingPathComponent("conflict.txt")
    try "base\n".write(to: file, atomically: true, encoding: .utf8)
    try runGit(["add", "conflict.txt"], in: repo)
    try runGit(["commit", "-m", "base"], in: repo)
    let baseBranch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    try runGit(["checkout", "-b", "ours"], in: repo)
    try "ours\n".write(to: file, atomically: true, encoding: .utf8)
    try runGit(["commit", "-am", "ours"], in: repo)

    try runGit(["checkout", "-b", "theirs", baseBranch], in: repo)
    try "theirs\n".write(to: file, atomically: true, encoding: .utf8)
    try runGit(["commit", "-am", "theirs"], in: repo)

    try runGit(["checkout", "ours"], in: repo)
    _ = try runGit(["merge", "theirs"], in: repo, allowFailure: true)
    return repo
}

private func replaceText(in textView: NSTextView,
                         range: NSRange,
                         with replacement: String,
                         shouldAllow: Bool = true,
                         _ message: String) {
    textView.setSelectedRange(range)
    let allowed = textView.shouldChangeText(in: range, replacementString: replacement)
    assertTrue(allowed == shouldAllow, message)
    guard allowed else { return }
    textView.textStorage?.replaceCharacters(in: range, with: replacement)
    textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    textView.didChangeText()
}

private func clickText(in textView: NSTextView,
                       containing needle: String,
                       window: NSWindow,
                       _ message: String) {
    guard let range = nsRange(of: needle, in: textView.string),
          let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        assertTrue(false, message)
        return
    }

    let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
    let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let origin = textView.textContainerOrigin
    let textPoint = NSPoint(x: origin.x + fragment.minX + 4,
                            y: origin.y + fragment.midY)
    let windowPoint = textView.convert(textPoint, to: nil)
    guard let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                         location: windowPoint,
                                         modifierFlags: [],
                                         timestamp: 0,
                                         windowNumber: window.windowNumber,
                                         context: nil,
                                         eventNumber: 0,
                                         clickCount: 1,
                                         pressure: 1) else {
        assertTrue(false, "\(message) creates mouse event")
        return
    }

    textView.mouseDown(with: event)
    _ = textContainer
}

private func clickLineNumberControl(in rootView: NSView,
                                    identifier: String,
                                    symbol: String,
                                    window: NSWindow,
                                    _ message: String) {
    guard let gutter = views(in: rootView, identifier: identifier).first,
          let label = gutter.accessibilityLabel(),
          let row = label.components(separatedBy: "\n").firstIndex(of: symbol) else {
        assertTrue(false, message)
        return
    }

    let font = textViews(in: rootView, identifier: "mergedSide").first?.font
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let rowHeight = ceil(font.ascender - font.descender + font.leading)
    let point = NSPoint(x: gutter.bounds.midX,
                        y: CGFloat(row) * rowHeight + rowHeight / 2)
    let windowPoint = gutter.convert(point, to: nil)
    guard let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                         location: windowPoint,
                                         modifierFlags: [],
                                         timestamp: 0,
                                         windowNumber: window.windowNumber,
                                         context: nil,
                                         eventNumber: 0,
                                         clickCount: 1,
                                         pressure: 1) else {
        assertTrue(false, "\(message) creates mouse event")
        return
    }

    gutter.mouseDown(with: event)
}

private func undoMergedText(in controller: MainWindowController, _ message: String) {
    assertTrue(!textViews(in: controller.view, identifier: "mergedSide").isEmpty, message)
    controller.undo(nil)
}

private func redoMergedText(in controller: MainWindowController, _ message: String) {
    assertTrue(!textViews(in: controller.view, identifier: "mergedSide").isEmpty, message)
    controller.redo(nil)
}

private func nsRange(of needle: String, in text: String) -> NSRange? {
    guard let range = text.range(of: needle) else { return nil }
    return NSRange(range, in: text)
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

    changedBlock.pick = .manual
    changedBlock.manualLines = ["manual", "merged"]
    assertTrue(document.canSave(), "bridge document can save after manual edit")
    let manualMerged = try document.mergedText()
    assertTrue(manualMerged == "one\nmanual\nmerged\nthree\n", "bridge merge after manual edit output")

    changedBlock.manualLines = []
    let emptyManualMerged = try document.mergedText()
    assertTrue(emptyManualMerged == "one\nthree\n", "bridge merge after empty manual edit output")

    #if !MCD_LOGGING_DISABLED
    guard let testLogDirectory else {
        assertTrue(false, "test log directory is available")
        return
    }
    let cppLog = try String(contentsOf: testLogDirectory.appendingPathComponent("cpp.log"), encoding: .utf8)
    assertTrue(cppLog.contains("Bridge requested diff"), "cpp.log contains bridge diff message")
    assertTrue(cppLog.contains("Merged text bytes"), "cpp.log contains merge message")
    #endif
}

private func testBridgeConflictDocumentParsing() throws {
    var error: NSError?
    guard let document = MDMakeConflictDocument("""
    before
    <<<<<<< HEAD
    ours
    ||||||| base
    base
    =======
    theirs
    >>>>>>> branch
    after

    """, &error) else {
        assertTrue(false, "bridge parses conflict document")
        return
    }

    assertTrue(error == nil, "conflict document parse has no error")
    assertTrue(document.blocks.count == 3, "conflict document has expected block count")
    assertTrue(document.blocks[1].kind == .changed, "conflict document creates changed block")
    assertTrue(document.blocks[1].leftLines == ["ours"], "conflict document left side")
    assertTrue(document.blocks[1].rightLines == ["theirs"], "conflict document right side ignores diff3 base")
    assertTrue(document.canSave() == false, "conflict document requires resolution")

    document.blocks[1].pick = .manual
    document.blocks[1].manualLines = ["resolved"]
    let merged = try document.mergedText()
    assertTrue(merged == "before\nresolved\nafter\n", "conflict document merged output removes markers")
}

private func testGitBridgeListsAndStagesConflict() throws {
    let repo = try makeConflictedRepository("git-bridge-conflict")
    let nested = repo.appendingPathComponent("subdir", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    var error: NSError?
    guard let rootPath = MDGitDiscoverRepository(nested.path, &error) else {
        assertTrue(false, "git repository is discovered")
        return
    }
    assertTrue(URL(fileURLWithPath: rootPath).standardizedFileURL.path == repo.standardizedFileURL.path,
               "git discovery returns repo root")

    guard let conflictFiles = MDGitConflictFiles(rootPath, &error) else {
        assertTrue(false, "git conflicts are listed")
        return
    }
    assertTrue(conflictFiles.contains { ($0.relativePath ?? "") == "conflict.txt" },
               "git conflict list includes conflicted path")

    let conflictFile = repo.appendingPathComponent("conflict.txt")
    var text = try String(contentsOf: conflictFile, encoding: .utf8)
    assertTrue(text.contains("<<<<<<<"), "test repo has conflict markers before resolution")
    try "resolved\n".write(to: conflictFile, atomically: true, encoding: .utf8)

    var stageError: NSError?
    assertTrue(MDGitStageFile(rootPath, "conflict.txt", &stageError), "resolved conflict stages successfully")
    assertTrue(stageError == nil, "staging has no error")
    text = try String(contentsOf: conflictFile, encoding: .utf8)
    assertTrue(!text.contains("<<<<<<<"), "resolved worktree file has no conflict markers")
    let unmerged = try runGit(["ls-files", "-u"], in: repo)
    assertTrue(unmerged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "staging resolved file clears unmerged index entries")
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

private func testPaneTextIsSelectableAndMergedPaneEditable() throws {
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
    assertTrue(unpicked?.isEditable == true, "merged pane is editable before pick")

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)

    let picked = textViews(in: controller.view, identifier: "mergedSide").first
    assertTrue(picked?.string.contains("right words") == true, "picked merged text appears in the native text view")
    assertTrue(picked?.string.contains("Unresolved") == false, "picked merged text remains placeholder-free")
    assertTrue(picked?.isSelectable == true, "picked merged text remains selectable")
    assertTrue(picked?.isEditable == true, "picked merged text remains editable")
}

private func testSidePickUndoRedoRestoresMergedState() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
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

private func testManualMergedEditEnablesSaveAndShowsManualText() throws {
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

private func testSameLineManualMergedEditDoesNotRerenderTextView() throws {
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

private func testManualMergedEditUndoRedoRestoresBlockState() throws {
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

private func testUndoPreservesCaretInsideChangedBlock() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Left" }?.performClick(nil)
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

private func testManualMergedEditNormalizesToRightPick() throws {
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

private func testManualMergedEditCanBreakLineAtEndOfChangedLine() throws {
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

private func testAllBlankRowsInDeletionBlockAreEditable() throws {
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

private func testMergedPaneAcceptsMultiLinePasteText() throws {
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

private func testMergedEditAllowsEqualRows() throws {
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

private func testUndoPreservesCaretInsideEqualRows() throws {
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

private func testEditingEqualLineAboveConflictDoesNotResolveConflict() throws {
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

private func testEditingAtEndOfEqualLineAboveConflictDoesNotResolveConflict() throws {
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

private func testMergedEditCanSpanMultipleBlocks() throws {
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

private func testCrossBlockMergedEditUndoRestoresEveryAffectedBlock() throws {
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

private func testDeletingManualMergedTextLeavesResolvedEmptyBlock() throws {
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

private func testPickingSmallerConflictKeepsLeftAndRightRowsVisible() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
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

private func testMainWindowGitMergeToolSaveWritesMergedPath() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
    layout(testWindow, controller)
    let save = buttons(in: controller.view).first { $0.title == "Save Merge" }
    assertTrue(save?.isEnabled == true, "mergetool save enables after resolution")
    save?.performClick(nil)

    assertTrue(completed == true, "mergetool reports successful completion after save")
    let saved = try String(contentsOf: merged, encoding: .utf8)
    assertTrue(saved == "before\ntheirs\nafter\n", "mergetool writes resolved output to merged path")
}

private func testMainWindowGitMergeToolCompactsLargeContextAndPreservesSave() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Right" }?.performClick(nil)
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

private func testMainWindowGitModeSavesAndStagesSelectedConflict() throws {
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

    buttons(in: controller.view).first { $0.title == "Use Left" }?.performClick(nil)
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

@main
private enum SwiftTests {
    static func main() {
        do {
            #if !MCD_LOGGING_DISABLED
            try testLoggerCreatesRunFolderAndPrunesOldRuns()
            #endif
            try testBridgeDiffMergeAndErrors()
            try testBridgeConflictDocumentParsing()
            try testGitBridgeListsAndStagesConflict()
            testMainWindowInitialState()
            try testMainWindowIdenticalFilesEnableSaveWithoutPick()
            try testMainWindowLoadsAndPicksDiff()
            testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane()
            testChangedRowsKeepStablePaneWidths()
            try testPaneTextIsSelectableAndMergedPaneEditable()
            try testMergedPaneTextBecomesSelectableAfterPick()
            try testSidePickUndoRedoRestoresMergedState()
            try testManualMergedEditEnablesSaveAndShowsManualText()
            try testSameLineManualMergedEditDoesNotRerenderTextView()
            try testManualMergedEditUndoRedoRestoresBlockState()
            try testUndoPreservesCaretInsideChangedBlock()
            try testManualMergedEditNormalizesToRightPick()
            try testManualMergedEditCanBreakLineAtEndOfChangedLine()
            try testAllBlankRowsInDeletionBlockAreEditable()
            try testMergedPaneAcceptsMultiLinePasteText()
            try testMergedEditAllowsEqualRows()
            try testUndoPreservesCaretInsideEqualRows()
            try testEditingEqualLineAboveConflictDoesNotResolveConflict()
            try testEditingAtEndOfEqualLineAboveConflictDoesNotResolveConflict()
            try testMergedEditCanSpanMultipleBlocks()
            try testCrossBlockMergedEditUndoRestoresEveryAffectedBlock()
            try testDeletingManualMergedTextLeavesResolvedEmptyBlock()
            try testPaneUsesOneNativeSelectionAcrossMultipleTextBlocks()
            try testNativeTextSelectionKeepsPartialWordRange()
            try testPickingOneBlockLeavesOtherMergedBlocksBlankAndUnsaved()
            try testPickingSmallerConflictKeepsLeftAndRightRowsVisible()
            try testLongLineSlidersMoveAllPanesTogetherWithoutChangingPaneWidths()
            try testMainWindowGitMergeToolSaveWritesMergedPath()
            try testMainWindowGitMergeToolCompactsLargeContextAndPreservesSave()
            try testMainWindowGitModeSavesAndStagesSelectedConflict()
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
