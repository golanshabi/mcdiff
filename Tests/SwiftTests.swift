import AppKit
import Foundation

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
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("swift.log").path), "swift.log exists")
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("cpp.log").path), "cpp.log exists")
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

    let useRight = buttons(in: controller.view).first { $0.title == "Use Right" }
    assertTrue(useRight != nil, "rendered Use Right button")
    useRight?.performClick(nil)

    let save = buttons(in: controller.view).first { $0.title == "Save Result" }
    assertTrue(save?.isEnabled == true, "save enables after picking a changed block")
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
}

@main
private enum SwiftTests {
    static func main() {
        do {
            try testLoggerCreatesRunFolderAndPrunesOldRuns()
            testMainWindowInitialState()
            try testMainWindowLoadsAndPicksDiff()
            testDeletionDiffRequiresExplicitPick()
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
