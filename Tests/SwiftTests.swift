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

private func labels(in view: NSView) -> [NSTextField] {
    allSubviews(of: view).compactMap { $0 as? NSTextField }
}

private func stackViews(in view: NSView) -> [NSStackView] {
    allSubviews(of: view).compactMap { $0 as? NSStackView }
}

private func stackViews(in view: NSView, identifier: String) -> [NSStackView] {
    stackViews(in: view).filter { $0.identifier?.rawValue == identifier }
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
    stackViews(in: view, identifier: identifier).compactMap { stack in
        guard let cgColor = stack.layer?.backgroundColor else { return nil }
        return colorComponents(NSColor(cgColor: cgColor) ?? .clear)
    }
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

    let labelText = labels(in: controller.view).map(\.stringValue).joined(separator: "\n")
    assertTrue(labelText.contains("1  alpha"), "identical files render first line")
    assertTrue(labelText.contains("2  beta"), "identical files render second line")
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

    let labelText = labels(in: controller.view).map(\.stringValue).joined(separator: "\n")
    assertTrue(labelText.contains("left"), "rendered left-side changed line")
    assertTrue(labelText.contains("right"), "rendered right-side changed line")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "leftSide"), redAtLeast: 0.8), "changed left side is red")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), greenAtLeast: 0.45), "changed right side is green")

    let useRight = buttons(in: controller.view).first { $0.title == "Use Right" }
    assertTrue(useRight != nil, "rendered Use Right button")
    useRight?.performClick(nil)
    layout(testWindow, controller)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "save enables after picking a changed block")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), blueAtLeast: 0.7), "picked right side is blue")
}

private func testDeletionDiffRequiresExplicitPick() {
    let controller = MainWindowController()
    controller.loadView()
    let testWindow = window(for: controller)
    layout(testWindow, controller)
    controller.load(left: URL(fileURLWithPath: "Tests/diff_1"),
                    right: URL(fileURLWithPath: "Tests/diff_2"))
    layout(testWindow, controller)

    let labelText = labels(in: controller.view).map(\.stringValue).joined(separator: "\n")
    assertTrue(labelText.contains("4  d"), "rendered deleted line from left file")
    assertTrue(labels(in: controller.view).contains { !$0.frame.isEmpty && !$0.isHidden }, "rendered labels have visible frames")

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == false, "deletion diff requires an explicit pick before saving")
    assertTrue(buttons(in: controller.view).contains { $0.title == "Use Left" }, "deletion diff renders Use Left")
    assertTrue(buttons(in: controller.view).contains { $0.title == "Use Right" }, "deletion diff renders Use Right")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "leftSide"), redAtLeast: 0.8), "deletion diff shows red deletion side")
    assertTrue(hasColor(backgroundColors(in: controller.view, identifier: "rightSide"), greenAtLeast: 0.45), "deletion diff shows green addition side")
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
            testDeletionDiffRequiresExplicitPick()
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
