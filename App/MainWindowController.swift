import AppKit

private final class PickButton: NSButton {
    weak var block: MDBlock?
    var picksLeft = false
}

private enum DiffPane: CaseIterable, Hashable {
    case left
    case merged
    case right

    var identifier: String {
        switch self {
            case .left:
                return "leftSide"
            case .merged:
                return "mergedSide"
            case .right:
                return "rightSide"
        }
    }
}

private final class PaneHorizontalSlider: NSSlider {
    let pane: DiffPane
    var wheelStep: Double = 0.08

    init(pane: DiffPane) {
        self.pane = pane
        super.init(frame: .zero)
        minValue = 0
        maxValue = 1
        doubleValue = 0
        isContinuous = true
        sliderType = .linear
    }

    required init?(coder: NSCoder) {
        fatalError("PaneHorizontalSlider does not support storyboards")
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }

        doubleValue = min(max(doubleValue + Double(delta) * wheelStep, minValue), maxValue)
        if let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

private final class PaneHorizontalState {
    var contentWidth: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var offset: CGFloat = 0

    var maxOffset: CGFloat {
        max(contentWidth - viewportWidth, 0)
    }

    func clampOffset() {
        offset = min(max(offset, 0), maxOffset)
    }
}

private protocol PaneTextClipViewDelegate: AnyObject {
    func paneTextClipView(_ clipView: PaneTextClipView, didScrollHorizontallyBy deltaX: CGFloat)
    func paneTextClipView(_ clipView: PaneTextClipView, didBeginSelectionAt characterIndex: Int)
    func paneTextClipView(_ clipView: PaneTextClipView, didDragSelectionTo windowPoint: NSPoint)
    func paneTextClipViewDidFinishSelection(_ clipView: PaneTextClipView)
    func paneTextClipViewWillUseNativeSelection(_ clipView: PaneTextClipView)
    func paneTextClipViewCopySelectedText(_ clipView: PaneTextClipView) -> Bool
}

private final class PaneTextView: NSTextView {
    weak var clipView: PaneTextClipView?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let clipView else {
            super.mouseDown(with: event)
            return
        }

        if event.clickCount > 1 {
            window?.makeFirstResponder(self)
            clipView.selectWord(with: event)
            return
        }

        window?.makeFirstResponder(self)
        clipView.beginSelection(with: event)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
                case .leftMouseDragged:
                    clipView.dragSelection(with: next)
                case .leftMouseUp:
                    clipView.finishSelection()
                    return
                default:
                    break
            }
        }
        clipView.finishSelection()
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        if abs(deltaX) > abs(event.scrollingDeltaY), abs(deltaX) > 0 {
            clipView?.forwardHorizontalScroll(deltaX)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copy(nil)
            return
        }

        super.keyDown(with: event)
    }

    override func copy(_ sender: Any?) {
        if clipView?.copySelectedTextToPasteboard() == true {
            return
        }
        super.copy(sender)
    }

    override func setSelectedRange(_ charRange: NSRange) {
        guard let clipView else {
            super.setSelectedRange(charRange)
            return
        }

        clipView.select(range: charRange)
    }

    override func selectedRange() -> NSRange {
        clipView?.selectedRange ?? super.selectedRange()
    }
}

final class PaneSelectionOverlayView: NSView {
    var selectedRects = [NSRect]() {
        didSet {
            isHidden = selectedRects.isEmpty
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.setFill()
        for rect in selectedRects {
            rect.intersection(bounds).fill()
        }
    }
}

private final class PaneTextClipView: NSView {
    let pane: DiffPane
    private let textView: PaneTextView
    private let selectionOverlay: PaneSelectionOverlayView
    private let selectableText: String
    private let textSize: NSSize
    private var customSelectedRange = NSRange(location: 0, length: 0)
    weak var delegate: PaneTextClipViewDelegate?

    private static var selectionAttributes: [NSAttributedString.Key: Any] {
        [
            .backgroundColor: NSColor.clear,
            .foregroundColor: NSColor.labelColor
        ]
    }

    var textOffset: CGFloat = 0 {
        didSet {
            needsLayout = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(textSize.height, 1))
    }

    init(text: String, selectableText: String, pane: DiffPane, font: NSFont) {
        self.pane = pane
        let displayText = text.isEmpty ? " " : text
        self.selectableText = selectableText
        textSize = PaneTextClipView.measuredSize(for: displayText, font: font)
        selectionOverlay = PaneSelectionOverlayView(frame: .zero)
        textView = PaneTextView(frame: .zero)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)TextClip")
        wantsLayer = true
        layer?.masksToBounds = true
        selectionOverlay.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)SelectionOverlay")
        selectionOverlay.isHidden = true
        textView.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)Text")
        textView.clipView = self
        textView.string = displayText
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = !selectableText.isEmpty
        textView.selectedTextAttributes = PaneTextClipView.selectionAttributes
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.focusRingType = .none
        addSubview(selectionOverlay)
        addSubview(textView)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("PaneTextClipView does not support storyboards")
    }

    override func layout() {
        super.layout()
        let textWidth = max(textSize.width, bounds.width + textOffset)
        let textHeight = max(textSize.height, bounds.height)
        let textFrame = NSRect(x: -textOffset, y: 0, width: textWidth, height: textHeight)
        selectionOverlay.frame = textFrame
        textView.frame = textFrame
        updateSelectionPresentation()
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        if abs(deltaX) > abs(event.scrollingDeltaY), abs(deltaX) > 0 {
            forwardHorizontalScroll(deltaX)
        } else {
            super.scrollWheel(with: event)
        }
    }

    fileprivate func forwardHorizontalScroll(_ deltaX: CGFloat) {
        delegate?.paneTextClipView(self, didScrollHorizontallyBy: deltaX)
    }

    fileprivate func beginSelection(with event: NSEvent) {
        delegate?.paneTextClipView(self, didBeginSelectionAt: characterIndex(for: event.locationInWindow))
    }

    fileprivate func dragSelection(with event: NSEvent) {
        delegate?.paneTextClipView(self, didDragSelectionTo: event.locationInWindow)
    }

    fileprivate func finishSelection() {
        delegate?.paneTextClipViewDidFinishSelection(self)
    }

    fileprivate func useNativeSelection() {
        delegate?.paneTextClipViewWillUseNativeSelection(self)
    }

    fileprivate func selectWord(with event: NSEvent) {
        delegate?.paneTextClipViewWillUseNativeSelection(self)
        guard textLength > 0 else { return }

        let index = min(characterIndex(for: event.locationInWindow), max(textLength - 1, 0))
        let proposedRange = NSRange(location: index, length: 0)
        select(range: textView.selectionRange(forProposedRange: proposedRange, granularity: .selectByWord))
    }

    fileprivate func copySelectedTextToPasteboard() -> Bool {
        delegate?.paneTextClipViewCopySelectedText(self) == true
    }

    fileprivate var textLength: Int {
        (selectableText as NSString).length
    }

    fileprivate var hasSelectableText: Bool {
        !selectableText.isEmpty
    }

    fileprivate var selectedRange: NSRange {
        customSelectedRange
    }

    fileprivate func characterIndex(for windowPoint: NSPoint) -> Int {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        let pointInTextView = textView.convert(windowPoint, from: nil)
        if pointInTextView.y <= textView.bounds.minY {
            return 0
        }
        if pointInTextView.y >= textView.bounds.maxY {
            return textLength
        }

        let containerOrigin = textView.textContainerOrigin
        let containerPoint = NSPoint(x: pointInTextView.x - containerOrigin.x,
                                     y: pointInTextView.y - containerOrigin.y)
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint,
                                                  in: textContainer,
                                                  fractionOfDistanceThroughGlyph: &fraction)
        var characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        if fraction > 0.5 {
            characterIndex += 1
        }
        return min(max(characterIndex, 0), textLength)
    }

    fileprivate func select(range: NSRange) {
        let location = min(max(range.location, 0), textLength)
        let maxLength = textLength - location
        let length = min(max(range.length, 0), maxLength)
        customSelectedRange = NSRange(location: location, length: length)
        updateSelectionPresentation()
        textView.needsDisplay = true
    }

    fileprivate func clearSelection() {
        select(range: NSRange(location: 0, length: 0))
    }

    fileprivate func selectedText() -> String? {
        let range = selectedRange
        guard range.length > 0,
              let swiftRange = Range(range, in: selectableText) else {
            return nil
        }
        return String(selectableText[swiftRange])
    }

    private func updateSelectionPresentation() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            selectionOverlay.selectedRects = []
            return
        }

        let textViewRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: textViewRange)

        guard selectedRange.length > 0 else {
            selectionOverlay.selectedRects = []
            return
        }

        layoutManager.addTemporaryAttributes([.foregroundColor: NSColor.white],
                                             forCharacterRange: selectedRange)
        layoutManager.ensureLayout(for: textContainer)

        let selectedGlyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange,
                                                          actualCharacterRange: nil)
        let origin = textView.textContainerOrigin
        var rects = [NSRect]()
        let nsString = textView.string as NSString
        layoutManager.enumerateLineFragments(forGlyphRange: selectedGlyphRange) { _, usedRect, _, lineGlyphRange, _ in
            var lineCharacterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange,
                                                                  actualGlyphRange: nil)
            lineCharacterRange = NSIntersectionRange(lineCharacterRange, self.selectedRange)
            while lineCharacterRange.length > 0 {
                let character = nsString.character(at: lineCharacterRange.location + lineCharacterRange.length - 1)
                guard character == 10 || character == 13 else { break }
                lineCharacterRange.length -= 1
            }

            guard lineCharacterRange.length > 0 else { return }

            let lineSelectedGlyphRange = layoutManager.glyphRange(forCharacterRange: lineCharacterRange,
                                                                  actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: lineSelectedGlyphRange,
                                                       in: textContainer)
            guard glyphRect.width > 0 else { return }

            rects.append(NSRect(x: glyphRect.origin.x + origin.x,
                                y: usedRect.origin.y + origin.y,
                                width: glyphRect.width,
                                height: usedRect.height).integral)
        }
        selectionOverlay.selectedRects = rects
    }

    private static func measuredSize(for text: String, font: NSFont) -> NSSize {
        let lines = text.components(separatedBy: "\n")
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxWidth = lines
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return (measuredLine as NSString).size(withAttributes: [.font: font]).width
            }
            .max() ?? 1
        return NSSize(width: ceil(maxWidth) + 1,
                      height: max(CGFloat(max(lines.count, 1)) * lineHeight, 1))
    }
}

final class MainWindowController: NSViewController, PaneTextClipViewDelegate {
    private struct ActivePaneSelection {
        let pane: DiffPane
        let anchorClip: PaneTextClipView
        let anchorIndex: Int
    }

    private let paneTextFont = NSFont.monospacedSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private let pickButtonSlotWidth: CGFloat = 92
    private let lineNumberWidth: CGFloat = 42
    private let paneInset: CGFloat = 8
    private let paneContentSpacing: CGFloat = 8
    private let horizontalScrollerHeight: CGFloat = 22
    private let horizontalWheelSensitivity: CGFloat = 3

    private let leftButton = NSButton(title: "Choose Left File", target: nil, action: nil)
    private let rightButton = NSButton(title: "Choose Right File", target: nil, action: nil)
    private let compareButton = NSButton(title: "Compare", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Result", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let horizontalScrollerRow = NSStackView()
    private let paneScrollerStack = NSStackView()

    private var leftURL: URL?
    private var rightURL: URL?
    private var document: MDDocument?
    private var paneScrollers = [DiffPane: PaneHorizontalSlider]()
    private var paneStates = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, PaneHorizontalState()) })
    private var paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
    private var sharedHorizontalValue: Double = 0
    private var activePaneSelection: ActivePaneSelection?

    override func loadView() {
        AppLogger.info("Loading main view.")
        view = NSView()

        let bar = NSStackView(views: [leftButton, rightButton, compareButton, saveButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.identifier = NSUserInterfaceItemIdentifier("verticalScroll")
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false

        configureHorizontalScrollers()

        let root = NSStackView(views: [bar, scroll, horizontalScrollerRow])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)
        ])
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        leftButton.target = self; leftButton.action = #selector(chooseLeft)
        rightButton.target = self; rightButton.action = #selector(chooseRight)
        compareButton.target = self; compareButton.action = #selector(compare)
        saveButton.target = self; saveButton.action = #selector(save)
        updateButtons()
        AppLogger.info("Main view loaded.")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshPaneViewportWidths()
    }

    func load(left: URL, right: URL) {
        AppLogger.info("Received files to load left=\(left.path) right=\(right.path)")
        leftURL = left
        rightURL = right
        compare()
    }

    @objc private func chooseLeft() {
        leftURL = pickFile()
        AppLogger.info("Left file selected: \(leftURL?.path ?? "none")")
        updateButtons()
    }

    @objc private func chooseRight() {
        rightURL = pickFile()
        AppLogger.info("Right file selected: \(rightURL?.path ?? "none")")
        updateButtons()
    }

    @objc private func compare() {
        guard let leftURL, let rightURL else { return }
        AppLogger.info("Starting compare left=\(leftURL.path) right=\(rightURL.path)")
        do {
            var error: NSError?
            document = MDMakeDiff(try String(contentsOf: leftURL, encoding: .utf8),
                                  try String(contentsOf: rightURL, encoding: .utf8),
                                  &error)
            if let error {
                AppLogger.error("Compare failed from bridge: \(error.localizedDescription)")
                show(error.localizedDescription)
            } else {
                AppLogger.info("Compare succeeded blocks=\(document?.blocks.count ?? 0)")
            }
            resetHorizontalOffsets()
            render(preservingVerticalPosition: false)
        } catch {
            AppLogger.error("Compare failed while reading files: \(error.localizedDescription)")
            show(error.localizedDescription)
        }
        updateButtons()
    }

    @objc private func save() {
        guard let document else { return }
        AppLogger.info("Starting save.")
        do {
            let text = try document.mergedText()
            let panel = NSSavePanel()
            if panel.runModal() == .OK, let url = panel.url {
                try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                AppLogger.info("Saved merged text to \(url.path) bytes=\(text.utf8.count)")
            } else {
                AppLogger.info("Save panel cancelled.")
            }
        } catch {
            AppLogger.error("Save failed: \(error.localizedDescription)")
            show(error.localizedDescription)
        }
    }

    private func render(preservingVerticalPosition: Bool) {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        updatePaneContentWidths()
        paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let document else { return }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        var mergedStartLine = 1
        for block in document.blocks {
            stack.addArrangedSubview(blockView(block, mergedStartLine: mergedStartLine))
            mergedStartLine += mergedOutputLineCount(for: block)
        }
        refreshPaneViewportWidths()
        if preservingVerticalPosition {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: previousVisibleOrigin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func blockView(_ block: MDBlock, mergedStartLine: Int) -> NSView {
        let row = NSStackView()
        row.identifier = NSUserInterfaceItemIdentifier("blockRow")
        row.orientation = .horizontal
        row.spacing = 0

        row.addArrangedSubview(pickButtonSlot(block, picksLeft: true))

        let panes = NSStackView()
        panes.orientation = .horizontal
        panes.spacing = 0
        panes.distribution = .fillEqually
        panes.setContentHuggingPriority(.defaultLow, for: .horizontal)
        panes.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        panes.addArrangedSubview(paneView(block, pane: .left, mergedStartLine: mergedStartLine))
        panes.addArrangedSubview(paneView(block, pane: .merged, mergedStartLine: mergedStartLine))
        panes.addArrangedSubview(paneView(block, pane: .right, mergedStartLine: mergedStartLine))
        row.addArrangedSubview(panes)

        row.addArrangedSubview(pickButtonSlot(block, picksLeft: false))
        return row
    }

    private func pickButtonSlot(_ block: MDBlock, picksLeft: Bool) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: pickButtonSlotWidth).isActive = true

        if block.kind == .changed {
            let button = PickButton(title: picksLeft ? "Use Left" : "Use Right", target: self, action: #selector(pick(_:)))
            button.block = block
            button.picksLeft = picksLeft
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        return view
    }

    private func paneView(_ block: MDBlock, pane: DiffPane, mergedStartLine: Int) -> NSView {
        let view = NSStackView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier(for: pane))
        view.orientation = .vertical
        view.spacing = 6
        view.alignment = .width
        view.edgeInsets = NSEdgeInsets(top: 0, left: paneInset, bottom: 0, right: paneInset)
        view.wantsLayer = true
        if let color = backgroundColor(for: block, pane: pane) {
            view.layer?.backgroundColor = color.cgColor
        }

        let display = displayedLines(for: block, pane: pane, mergedStartLine: mergedStartLine)
        let content = NSStackView()
        content.orientation = .horizontal
        content.spacing = paneContentSpacing
        content.alignment = .top
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if pane != .merged {
            let numbers = NSTextField(labelWithString: lineNumberText(lines: display.lines, start: display.start))
            numbers.identifier = NSUserInterfaceItemIdentifier("\(identifier(for: pane))LineNumbers")
            numbers.alignment = .right
            numbers.textColor = .secondaryLabelColor
            numbers.font = lineNumberFont
            numbers.lineBreakMode = .byClipping
            numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
            content.addArrangedSubview(numbers)
        }

        let text = display.lines.joined(separator: "\n")
        let clip = PaneTextClipView(text: text,
                                    selectableText: selectableText(for: block, pane: pane, displayText: text),
                                    pane: pane,
                                    font: paneTextFont)
        clip.delegate = self
        clip.textOffset = paneStates[pane]?.offset ?? 0
        paneTextClipViews[pane, default: []].append(clip)
        content.addArrangedSubview(clip)

        view.addArrangedSubview(content)
        return view
    }

    private func selectableText(for block: MDBlock, pane: DiffPane, displayText: String) -> String {
        guard !(pane == .merged && block.kind == .changed && block.pick == .unpicked) else {
            return ""
        }
        return displayText
    }

    private func identifier(for pane: DiffPane) -> String {
        pane.identifier
    }

    private func backgroundColor(for block: MDBlock, pane: DiffPane) -> NSColor? {
        guard block.kind == .changed else { return nil }

        switch pane {
            case .left:
                return block.pick == .left ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemRed.withAlphaComponent(0.16)
            case .merged:
                return block.pick == .unpicked ? NSColor.systemOrange.withAlphaComponent(0.16) : nil
            case .right:
                return block.pick == .right ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemGreen.withAlphaComponent(0.16)
        }
    }

    private func displayedLines(for block: MDBlock, pane: DiffPane, mergedStartLine: Int) -> (lines: [String], start: Int?) {
        switch pane {
            case .left:
                return (block.leftLines ?? [], block.leftStartLine)
            case .right:
                return (block.rightLines ?? [], block.rightStartLine)
            case .merged:
                return mergedLines(for: block, start: mergedStartLine)
        }
    }

    private func lineNumberText(lines: [String], start: Int?) -> String {
        let lineCount = max(lines.count, 1)
        guard let start, start > 0 else {
            return String(repeating: "\n", count: lineCount - 1)
        }

        return (0..<lineCount).map { index in
            guard index < lines.count, !lines[index].isEmpty else { return "" }
            return "\(start + index)"
        }.joined(separator: "\n")
    }

    private func mergedLines(for block: MDBlock, start: Int) -> (lines: [String], start: Int?) {
        if block.kind == .equal {
            return (block.leftLines ?? [], start)
        }

        switch block.pick {
            case .left:
                return (block.leftLines ?? [], start)
            case .right:
                return (block.rightLines ?? [], start)
            case .unpicked:
                return (["Unresolved"], nil)
            @unknown default:
                return (["Unresolved"], nil)
        }
    }

    private func mergedOutputLineCount(for block: MDBlock) -> Int {
        if block.kind == .equal {
            return block.leftLines?.count ?? 0
        }

        switch block.pick {
            case .left:
                return block.leftLines?.count ?? 0
            case .right:
                return block.rightLines?.count ?? 0
            case .unpicked:
                return 0
            @unknown default:
                return 0
        }
    }

    @objc private func pick(_ sender: PickButton) {
        guard let block = sender.block else { return }
        block.pick = sender.picksLeft ? .left : .right
        AppLogger.info("Picked \(sender.picksLeft ? "left" : "right") for changed block left_start=\(block.leftStartLine) right_start=\(block.rightStartLine)")
        render(preservingVerticalPosition: true)
        updateButtons()
    }

    @objc private func scrollPaneHorizontally(_ sender: PaneHorizontalSlider) {
        applySharedHorizontalValue(sender.doubleValue)
    }

    fileprivate func paneTextClipView(_ clipView: PaneTextClipView, didScrollHorizontallyBy deltaX: CGFloat) {
        let maxOffset = sharedMaxOffset()
        guard maxOffset > 0 else { return }
        applySharedHorizontalValue(sharedHorizontalValue + Double(deltaX * horizontalWheelSensitivity / maxOffset))
    }

    fileprivate func paneTextClipView(_ clipView: PaneTextClipView, didBeginSelectionAt characterIndex: Int) {
        clearSelections(in: clipView.pane, except: nil)
        guard clipView.hasSelectableText else {
            activePaneSelection = nil
            return
        }

        activePaneSelection = ActivePaneSelection(pane: clipView.pane,
                                                 anchorClip: clipView,
                                                 anchorIndex: characterIndex)
        updateActiveSelection(endingAt: clipView, characterIndex: characterIndex)
    }

    fileprivate func paneTextClipView(_ clipView: PaneTextClipView, didDragSelectionTo windowPoint: NSPoint) {
        guard let activePaneSelection,
              activePaneSelection.pane == clipView.pane,
              let targetClip = targetClip(in: clipView.pane, for: windowPoint) else {
            return
        }

        updateActiveSelection(endingAt: targetClip,
                              characterIndex: targetClip.characterIndex(for: windowPoint))
    }

    fileprivate func paneTextClipViewDidFinishSelection(_ clipView: PaneTextClipView) {
        if activePaneSelection?.pane == clipView.pane {
            activePaneSelection = nil
        }
    }

    fileprivate func paneTextClipViewWillUseNativeSelection(_ clipView: PaneTextClipView) {
        activePaneSelection = nil
        clearSelections(in: clipView.pane, except: clipView)
    }

    fileprivate func paneTextClipViewCopySelectedText(_ clipView: PaneTextClipView) -> Bool {
        copySelectedTextToPasteboard(in: clipView.pane)
    }

    @objc func copy(_ sender: Any?) {
        _ = copySelectedTextToPasteboard(in: nil)
    }

    private func copySelectedTextToPasteboard(in pane: DiffPane?) -> Bool {
        let panes = pane.map { [$0] } ?? DiffPane.allCases
        let selectedChunks = panes
            .flatMap { paneTextClipViews[$0] ?? [] }
            .compactMap { $0.selectedText() }
        guard !selectedChunks.isEmpty else {
            AppLogger.info("Copy requested with no selected pane text.")
            return false
        }

        let pasteboard = NSPasteboard.general
        let selectedText = selectedChunks.joined(separator: "\n")
        pasteboard.clearContents()
        let copied = pasteboard.setString(selectedText, forType: .string)
            || pasteboard.writeObjects([selectedText as NSString])
        if copied {
            AppLogger.info("Copied selected pane text bytes=\(selectedText.utf8.count)")
        } else {
            AppLogger.error("Failed to write selected pane text to pasteboard.")
        }
        return copied
    }

    private func updateActiveSelection(endingAt targetClip: PaneTextClipView, characterIndex targetIndex: Int) {
        guard let activePaneSelection,
              activePaneSelection.pane == targetClip.pane,
              let clips = paneTextClipViews[targetClip.pane],
              let anchorClipIndex = clips.firstIndex(where: { $0 === activePaneSelection.anchorClip }),
              let targetClipIndex = clips.firstIndex(where: { $0 === targetClip }) else {
            return
        }

        if anchorClipIndex == targetClipIndex {
            for (index, clip) in clips.enumerated() {
                guard index == anchorClipIndex else {
                    clip.clearSelection()
                    continue
                }
                clip.select(range: range(from: activePaneSelection.anchorIndex, to: targetIndex))
            }
            return
        }

        let lowerIndex = min(anchorClipIndex, targetClipIndex)
        let upperIndex = max(anchorClipIndex, targetClipIndex)
        let isForwardSelection = anchorClipIndex < targetClipIndex

        for (index, clip) in clips.enumerated() {
            guard index >= lowerIndex && index <= upperIndex else {
                clip.clearSelection()
                continue
            }

            if isForwardSelection {
                if index == anchorClipIndex {
                    clip.select(range: range(from: activePaneSelection.anchorIndex, to: clip.textLength))
                } else if index == targetClipIndex {
                    clip.select(range: range(from: 0, to: targetIndex))
                } else {
                    clip.select(range: range(from: 0, to: clip.textLength))
                }
            } else {
                if index == targetClipIndex {
                    clip.select(range: range(from: targetIndex, to: clip.textLength))
                } else if index == anchorClipIndex {
                    clip.select(range: range(from: 0, to: activePaneSelection.anchorIndex))
                } else {
                    clip.select(range: range(from: 0, to: clip.textLength))
                }
            }
        }
    }

    private func targetClip(in pane: DiffPane, for windowPoint: NSPoint) -> PaneTextClipView? {
        let clips = (paneTextClipViews[pane] ?? []).filter(\.hasSelectableText)
        if let containingClip = clips.first(where: { clip in
            clip.bounds.contains(clip.convert(windowPoint, from: nil))
        }) {
            return containingClip
        }

        return clips.min { lhs, rhs in
            let lhsY = lhs.convert(NSPoint(x: lhs.bounds.midX, y: lhs.bounds.midY), to: nil).y
            let rhsY = rhs.convert(NSPoint(x: rhs.bounds.midX, y: rhs.bounds.midY), to: nil).y
            return abs(lhsY - windowPoint.y) < abs(rhsY - windowPoint.y)
        }
    }

    private func clearSelections(in pane: DiffPane, except keptClip: PaneTextClipView?) {
        for clip in paneTextClipViews[pane] ?? [] where clip !== keptClip {
            clip.clearSelection()
        }
    }

    private func range(from start: Int, to end: Int) -> NSRange {
        let location = min(start, end)
        return NSRange(location: location, length: abs(end - start))
    }

    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func updateButtons() {
        compareButton.isEnabled = leftURL != nil && rightURL != nil
        saveButton.isEnabled = document?.canSave() == true
        AppLogger.info("Updated buttons compare_enabled=\(compareButton.isEnabled) save_enabled=\(saveButton.isEnabled)")
    }

    private func configureHorizontalScrollers() {
        horizontalScrollerRow.orientation = .horizontal
        horizontalScrollerRow.spacing = 0
        horizontalScrollerRow.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)

        paneScrollerStack.orientation = .horizontal
        paneScrollerStack.spacing = 0
        paneScrollerStack.distribution = .fillEqually
        paneScrollerStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paneScrollerStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        horizontalScrollerRow.addArrangedSubview(horizontalScrollerSpacer(width: pickButtonSlotWidth))
        for pane in DiffPane.allCases {
            let scroller = PaneHorizontalSlider(pane: pane)
            scroller.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)HorizontalScroller")
            scroller.target = self
            scroller.action = #selector(scrollPaneHorizontally(_:))
            scroller.controlSize = .regular
            scroller.isEnabled = false
            scroller.doubleValue = 0
            scroller.heightAnchor.constraint(equalToConstant: horizontalScrollerHeight).isActive = true
            paneScrollers[pane] = scroller
            paneScrollerStack.addArrangedSubview(scroller)
        }
        horizontalScrollerRow.addArrangedSubview(paneScrollerStack)
        horizontalScrollerRow.addArrangedSubview(horizontalScrollerSpacer(width: pickButtonSlotWidth))
    }

    private func horizontalScrollerSpacer(width: CGFloat) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    private func resetHorizontalOffsets() {
        sharedHorizontalValue = 0
        for state in paneStates.values {
            state.offset = 0
        }
        updateHorizontalScrollers()
    }

    private func updatePaneContentWidths() {
        let sharedContentWidth = DiffPane.allCases
            .map(measuredContentWidth(for:))
            .max() ?? 0
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.contentWidth = sharedContentWidth
        }
        applySharedHorizontalValue(sharedHorizontalValue)
    }

    private func measuredContentWidth(for pane: DiffPane) -> CGFloat {
        guard let document else { return 0 }
        var maxWidth: CGFloat = 1
        for block in document.blocks {
            for line in widthCandidateLines(for: block, pane: pane) {
                maxWidth = max(maxWidth, measuredLineWidth(line))
            }
        }
        return maxWidth
    }

    private func widthCandidateLines(for block: MDBlock, pane: DiffPane) -> [String] {
        switch pane {
            case .left:
                return block.leftLines ?? []
            case .right:
                return block.rightLines ?? []
            case .merged:
                if block.kind == .equal {
                    return block.leftLines ?? []
                }

                var lines = ["Unresolved"]
                lines.append(contentsOf: block.leftLines ?? [])
                lines.append(contentsOf: block.rightLines ?? [])
                return lines
        }
    }

    private func measuredLineWidth(_ line: String) -> CGFloat {
        let text = line.isEmpty ? " " : line
        let width = (text as NSString).size(withAttributes: [.font: paneTextFont]).width
        return ceil(width) + 1
    }

    private func refreshPaneViewportWidths() {
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.viewportWidth = paneTextClipViews[pane]?.map(\.bounds.width).max() ?? 0
        }
        applySharedHorizontalValue(sharedHorizontalValue)
    }

    private func applySharedHorizontalValue(_ value: Double) {
        sharedHorizontalValue = min(max(value, 0), 1)
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.offset = CGFloat(sharedHorizontalValue) * state.maxOffset
            state.clampOffset()
            applyHorizontalOffset(for: pane)
        }
        updateHorizontalScrollers()
    }

    private func applyHorizontalOffset(for pane: DiffPane) {
        guard let state = paneStates[pane] else { return }
        for clip in paneTextClipViews[pane] ?? [] {
            clip.textOffset = state.offset
        }
    }

    private func updateHorizontalScrollers() {
        for pane in DiffPane.allCases {
            updateHorizontalScroller(for: pane)
        }
    }

    private func updateHorizontalScroller(for pane: DiffPane) {
        guard let scroller = paneScrollers[pane] else { return }
        scroller.isEnabled = sharedMaxOffset() > 0.5
        scroller.doubleValue = sharedHorizontalValue
    }

    private func sharedMaxOffset() -> CGFloat {
        paneStates.values.map(\.maxOffset).max() ?? 0
    }

    private func show(_ message: String) {
        AppLogger.error("Showing alert: \(message)")
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
