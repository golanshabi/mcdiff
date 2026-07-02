import AppKit
import Foundation

var testLogDirectory: URL?

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Swift test failed: \(message)\n", stderr)
        exit(1)
    }
}

func temporaryDirectory(_ name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mcdiff-swift-tests-\(getpid())-\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func allSubviews(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

func buttons(in view: NSView) -> [NSButton] {
    allSubviews(of: view).compactMap { $0 as? NSButton }
}

func sliders(in view: NSView) -> [NSSlider] {
    allSubviews(of: view).compactMap { $0 as? NSSlider }
}

func labels(in view: NSView) -> [NSTextField] {
    allSubviews(of: view).compactMap { $0 as? NSTextField }
}

func textViews(in view: NSView) -> [NSTextView] {
    allSubviews(of: view).compactMap { $0 as? NSTextView }
}

func popUpButtons(in view: NSView) -> [NSPopUpButton] {
    allSubviews(of: view).compactMap { $0 as? NSPopUpButton }
}

func views(in view: NSView, identifier: String) -> [NSView] {
    allSubviews(of: view).filter { $0.identifier?.rawValue == identifier }
}

func labels(in view: NSView, identifier: String) -> [NSTextField] {
    views(in: view, identifier: identifier).flatMap { matchedView in
        allSubviews(of: matchedView).compactMap { $0 as? NSTextField }
    }
}

func textViews(in view: NSView, identifier: String) -> [NSTextView] {
    views(in: view, identifier: identifier).flatMap { matchedView in
        allSubviews(of: matchedView).compactMap { $0 as? NSTextView }
    }
}

func text(in view: NSView, identifier: String) -> String {
    let selectableText = textViews(in: view, identifier: identifier)
    if !selectableText.isEmpty {
        return selectableText.map(\.string).joined(separator: "\n")
    }

    return labels(in: view, identifier: identifier).map(\.stringValue).joined(separator: "\n")
}

func renderedText(in view: NSView) -> String {
    (labels(in: view).map(\.stringValue) + textViews(in: view).map(\.string)).joined(separator: "\n")
}

func labelString(in view: NSView, identifier: String) -> String {
    labels(in: view)
        .filter { $0.identifier?.rawValue == identifier }
        .map(\.stringValue)
        .joined(separator: "\n")
}

func labelStrings(in view: NSView, identifier: String) -> [String] {
    labels(in: view)
        .filter { $0.identifier?.rawValue == identifier }
        .map(\.stringValue)
}

func textLines(in view: NSView, identifier: String) -> [String] {
    text(in: view, identifier: identifier)
        .components(separatedBy: "\n")
}

func stackViews(in view: NSView) -> [NSStackView] {
    allSubviews(of: view).compactMap { $0 as? NSStackView }
}

func stackViews(in view: NSView, identifier: String) -> [NSStackView] {
    stackViews(in: view).filter { $0.identifier?.rawValue == identifier }
}

func horizontalControl(in view: NSView, identifier: String) -> NSSlider? {
    sliders(in: view).first { $0.identifier?.rawValue == identifier }
}

func scrollView(in view: NSView, identifier: String) -> NSScrollView? {
    allSubviews(of: view)
        .compactMap { $0 as? NSScrollView }
        .first { $0.identifier?.rawValue == identifier }
}

func sendSliderAction(_ slider: NSSlider) {
    guard let action = slider.action else {
        assertTrue(false, "slider has an action")
        return
    }
    _ = slider.sendAction(action, to: slider.target)
}

@discardableResult
func runGit(_ arguments: [String],
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

func makeConflictedRepository(_ name: String) throws -> URL {
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

func replaceText(in textView: NSTextView,
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

func clickText(in textView: NSTextView,
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

func clickLineNumberControl(in rootView: NSView,
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

func undoMergedText(in controller: MainWindowController, _ message: String) {
    assertTrue(!textViews(in: controller.view, identifier: "mergedSide").isEmpty, message)
    controller.undo(nil)
}

func redoMergedText(in controller: MainWindowController, _ message: String) {
    assertTrue(!textViews(in: controller.view, identifier: "mergedSide").isEmpty, message)
    controller.redo(nil)
}

func nsRange(of needle: String, in text: String) -> NSRange? {
    guard let range = text.range(of: needle) else { return nil }
    return NSRange(range, in: text)
}

func textLabelOrigins(in view: NSView, clipIdentifier: String) -> [CGFloat] {
    views(in: view, identifier: clipIdentifier).compactMap { clip in
        allSubviews(of: clip).compactMap { ($0 as? NSTextView)?.frame.origin.x }.first
    }
}

func paneWidths(in view: NSView, identifier: String) -> [CGFloat] {
    views(in: view, identifier: identifier).map(\.frame.width)
}

func assertStableWidths(_ widths: [CGFloat], _ message: String) {
    guard let first = widths.first else {
        assertTrue(false, "\(message) has widths")
        return
    }
    for width in widths {
        assertTrue(abs(width - first) < 1.0, message)
    }
}

func window(for controller: MainWindowController) -> NSWindow {
    NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
             styleMask: [.titled, .closable, .miniaturizable, .resizable],
             backing: .buffered,
             defer: false)
}

func layout(_ window: NSWindow, _ controller: MainWindowController) {
    window.contentViewController = controller
    window.layoutIfNeeded()
    controller.view.layoutSubtreeIfNeeded()
}

func colorComponents(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
}

func backgroundColors(in view: NSView) -> [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)] {
    stackViews(in: view).compactMap { stack in
        guard let cgColor = stack.layer?.backgroundColor else { return nil }
        return colorComponents(NSColor(cgColor: cgColor) ?? .clear)
    }
}

func backgroundColors(in view: NSView,
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

func hasColor(_ colors: [(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)],
                      redAtLeast minRed: CGFloat = 0,
                      greenAtLeast minGreen: CGFloat = 0,
                      blueAtLeast minBlue: CGFloat = 0,
                      alphaAtLeast minAlpha: CGFloat = 0.01) -> Bool {
    colors.contains { color in
        color.red >= minRed && color.green >= minGreen && color.blue >= minBlue && color.alpha >= minAlpha
    }
}
