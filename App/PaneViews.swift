import AppKit

final class PickButton: NSButton {
    weak var block: MDBlock?
    var picksLeft = false
}

enum DiffPane: CaseIterable, Hashable {
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

final class PaneHorizontalSlider: NSSlider {
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

final class PaneHorizontalState {
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

protocol PaneTextClipViewDelegate: AnyObject {
    func paneTextClipView(_ clipView: PaneTextClipView, didScrollHorizontallyBy deltaX: CGFloat)
}

final class PaneTextView: NSTextView {
    weak var clipView: PaneTextClipView?
    var undoHandler: (() -> Void)?
    var redoHandler: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        if abs(deltaX) > abs(event.scrollingDeltaY), abs(deltaX) > 0 {
            clipView?.forwardHorizontalScroll(deltaX)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        guard isEditable, let string = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        insertText(string, replacementRange: selectedRange())
    }

    @objc func undo(_ sender: Any?) {
        guard let undoHandler else {
            NSSound.beep()
            return
        }

        undoHandler()
    }

    @objc func redo(_ sender: Any?) {
        guard let redoHandler else {
            NSSound.beep()
            return
        }

        redoHandler()
    }
}

struct PaneBackgroundRun {
    let startRow: Int
    let rowCount: Int
    let color: NSColor
}

enum CollapsedContextAction {
    case expandAbove
    case expandBelow
    case expandAll
}

struct PaneLineNumberControl {
    let symbol: String
    let blockIndex: Int
    let action: CollapsedContextAction
}

final class PaneColumnView: NSView {
    var backgroundRuns = [PaneBackgroundRun]() {
        didSet {
            needsDisplay = true
        }
    }
    var lineHeight: CGFloat = 1 {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for run in backgroundRuns {
            let rect = NSRect(x: 0,
                              y: CGFloat(run.startRow) * lineHeight,
                              width: bounds.width,
                              height: CGFloat(run.rowCount) * lineHeight)
            guard rect.intersects(dirtyRect) else { continue }
            run.color.setFill()
            rect.fill()
        }
    }
}

final class PaneLineNumberView: NSView {
    private var lineNumberLines: [String]
    private var controls: [Int: PaneLineNumberControl]
    private let font: NSFont
    private let controlFont: NSFont
    private let lineHeight: CGFloat
    private let clickHandler: (Int, CollapsedContextAction) -> Void

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric,
               height: max(CGFloat(rowCount) * lineHeight, 1))
    }

    init(lineNumberLines: [String],
         controls: [Int: PaneLineNumberControl],
         font: NSFont,
         lineHeight: CGFloat,
         clickHandler: @escaping (Int, CollapsedContextAction) -> Void) {
        self.lineNumberLines = lineNumberLines
        self.controls = controls
        self.font = font
        self.controlFont = NSFont.systemFont(ofSize: font.pointSize + 1, weight: .semibold)
        self.lineHeight = lineHeight
        self.clickHandler = clickHandler
        super.init(frame: .zero)
        setAccessibilityLabel(displayLines.joined(separator: "\n"))
        toolTip = "Expand hidden context"
    }

    required init?(coder: NSCoder) {
        fatalError("PaneLineNumberView does not support storyboards")
    }

    func update(lineNumberLines: [String], controls: [Int: PaneLineNumberControl]) {
        self.lineNumberLines = lineNumberLines
        self.controls = controls
        setAccessibilityLabel(displayLines.joined(separator: "\n"))
        invalidateIntrinsicContentSize()
        needsDisplay = true
        resetCursorRects()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let controlParagraph = NSMutableParagraphStyle()
        controlParagraph.alignment = .center

        for row in 0..<rowCount {
            let rowRect = NSRect(x: 0,
                                 y: CGFloat(row) * lineHeight,
                                 width: bounds.width,
                                 height: lineHeight)
            guard rowRect.intersects(dirtyRect) else { continue }

            if let control = controls[row] {
                let pillRect = rowRect.insetBy(dx: 5, dy: 2)
                NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
                NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()
                (control.symbol as NSString).draw(with: rowRect.insetBy(dx: 0, dy: 1),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                  attributes: [
                                                      .font: controlFont,
                                                      .foregroundColor: NSColor.controlAccentColor,
                                                      .paragraphStyle: controlParagraph
                                                  ])
            } else {
                let line = lineNumberLines.indices.contains(row) ? lineNumberLines[row] : ""
                (line as NSString).draw(with: rowRect.insetBy(dx: 0, dy: 1),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: [
                                             .font: font,
                                             .foregroundColor: NSColor.secondaryLabelColor,
                                             .paragraphStyle: paragraph
                                         ])
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = Int(point.y / lineHeight)
        guard let control = controls[row] else {
            super.mouseDown(with: event)
            return
        }
        clickHandler(control.blockIndex, control.action)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for row in controls.keys {
            addCursorRect(rowRect(for: row), cursor: .pointingHand)
        }
    }

    private var rowCount: Int {
        max(lineNumberLines.count, (controls.keys.max() ?? -1) + 1)
    }

    private func rowRect(for row: Int) -> NSRect {
        NSRect(x: 0,
               y: CGFloat(row) * lineHeight,
               width: bounds.width,
               height: lineHeight)
    }

    private var displayLines: [String] {
        (0..<rowCount).map { row in
            if let control = controls[row] {
                return control.symbol
            }
            return lineNumberLines.indices.contains(row) ? lineNumberLines[row] : ""
        }
    }
}

final class PaneTextClipView: NSView {
    let pane: DiffPane
    private let textView: PaneTextView
    private let lineHeight: CGFloat
    private var textSize: NSSize
    weak var delegate: PaneTextClipViewDelegate?

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

    var editableTextView: NSTextView {
        textView
    }

    init(text: String,
         pane: DiffPane,
         font: NSFont,
         lineHeight: CGFloat,
         isEditable: Bool = false,
         textDelegate: NSTextViewDelegate? = nil,
         undoHandler: (() -> Void)? = nil,
         redoHandler: (() -> Void)? = nil) {
        self.pane = pane
        self.lineHeight = lineHeight
        let measuredText = text.isEmpty ? " " : text
        textSize = PaneTextClipView.measuredSize(for: measuredText, font: font, lineHeight: lineHeight)
        textView = PaneTextView(frame: .zero)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)TextClip")
        wantsLayer = true
        layer?.masksToBounds = true
        textView.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)Text")
        textView.clipView = self
        textView.textStorage?.setAttributedString(PaneTextClipView.attributedString(for: text,
                                                                                    font: font,
                                                                                    lineHeight: lineHeight))
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.undoHandler = undoHandler
        textView.redoHandler = redoHandler
        textView.delegate = textDelegate
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
        textView.frame = textFrame
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

    func refreshTextLayout(afterReplacing range: NSRange, replacementText: String) {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let measuredText = replacementText.isEmpty ? " " : replacementText
        let replacementSize = PaneTextClipView.measuredSize(for: measuredText, font: font, lineHeight: lineHeight)
        textSize = NSSize(width: max(textSize.width, replacementSize.width),
                          height: textSize.height)
        invalidateIntrinsicContentSize()
        needsLayout = true

        let textLength = (textView.string as NSString).length
        let location = min(range.location, textLength)
        let availableLength = max(textLength - location, 0)
        let replacementLength = (replacementText as NSString).length
        let length = min(max(range.length, replacementLength), availableLength)
        let displayRange = NSRange(location: location, length: length)
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.invalidateLayout(forCharacterRange: displayRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: displayRange)
            layoutManager.ensureLayout(for: textContainer)
        }

        setNeedsDisplay(bounds)
        textView.setNeedsDisplay(textView.bounds)
        textView.needsDisplay = true
        needsDisplay = true
        superview?.needsDisplay = true
        layoutSubtreeIfNeeded()
        textView.displayIfNeeded()
        displayIfNeeded()
        superview?.displayIfNeeded()
    }

    func replaceText(_ text: String, preserveSelection: Bool = false) {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let selection = textView.selectedRange()
        if textView.string != text {
            textView.textStorage?.setAttributedString(PaneTextClipView.attributedString(for: text,
                                                                                        font: font,
                                                                                        lineHeight: lineHeight))
        }
        refreshTextLayoutForCurrentText()
        if preserveSelection {
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length),
                                              length: min(selection.length, max(length - min(selection.location, length), 0))))
        }
    }

    func refreshTextLayoutForCurrentText() {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let measuredText = textView.string.isEmpty ? " " : textView.string
        textSize = PaneTextClipView.measuredSize(for: measuredText, font: font, lineHeight: lineHeight)
        invalidateIntrinsicContentSize()
        needsLayout = true
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
            layoutManager.ensureLayout(for: textContainer)
        }
        setNeedsDisplay(bounds)
        textView.setNeedsDisplay(textView.bounds)
        textView.needsDisplay = true
        needsDisplay = true
        superview?.needsDisplay = true
    }

    private static func measuredSize(for text: String, font: NSFont, lineHeight: CGFloat) -> NSSize {
        let lines = text.components(separatedBy: "\n")
        let maxWidth = lines
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return (measuredLine as NSString).size(withAttributes: [.font: font]).width
            }
            .max() ?? 1
        return NSSize(width: ceil(maxWidth) + 1,
                      height: max(CGFloat(max(lines.count, 1)) * lineHeight, 1))
    }

    private static func attributedString(for text: String, font: NSFont, lineHeight: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
    }
}
