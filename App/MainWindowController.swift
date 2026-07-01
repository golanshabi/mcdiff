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
}

private final class PaneTextView: NSTextView {
    weak var clipView: PaneTextClipView?

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
}

struct PaneBackgroundRun {
    let startRow: Int
    let rowCount: Int
    let color: NSColor
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

private final class PaneTextClipView: NSView {
    let pane: DiffPane
    private let textView: PaneTextView
    private let textSize: NSSize
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

    fileprivate var editableTextView: NSTextView {
        textView
    }

    init(text: String,
         pane: DiffPane,
         font: NSFont,
         lineHeight: CGFloat,
         isEditable: Bool = false,
         textDelegate: NSTextViewDelegate? = nil) {
        self.pane = pane
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

final class MainWindowController: NSViewController, PaneTextClipViewDelegate, NSTextViewDelegate {
    private struct PaneRenderContent {
        var textLines = [String]()
        var lineNumberLines = [String]()
        var backgroundRuns = [PaneBackgroundRun]()
    }

    private struct BlockRenderSlot {
        let block: MDBlock
        let rowCount: Int
    }

    private struct RenderPlan {
        var panes: [DiffPane: PaneRenderContent]
        var blockSlots: [BlockRenderSlot]
        var mergedTextRanges: [MergedBlockTextRange]
        var totalRows: Int
    }

    private struct MergedBlockTextRange {
        let blockIndex: Int
        let characterRange: NSRange
        let isEditable: Bool
    }

    private struct PendingMergedEdit {
        let blockIndex: Int
        let oldBlockRange: NSRange
        let affectedRange: NSRange
        let replacement: String
    }

    private struct PendingMergedSelection {
        let blockIndex: Int
        let relativeLocation: Int
        let length: Int
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
    private weak var mergedTextView: NSTextView?
    private var mergedTextRanges = [MergedBlockTextRange]()
    private var pendingMergedEdit: PendingMergedEdit?
    private var pendingMergedSelection: PendingMergedSelection?
    private var sharedHorizontalValue: Double = 0

    private var lineHeight: CGFloat {
        ceil(paneTextFont.ascender - paneTextFont.descender + paneTextFont.leading)
    }

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
            pendingMergedEdit = nil
            pendingMergedSelection = nil
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
        mergedTextView = nil
        mergedTextRanges = []
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let document else { return }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        let plan = renderPlan(for: document)
        mergedTextRanges = plan.mergedTextRanges
        stack.addArrangedSubview(diffTableView(for: plan))
        refreshPaneViewportWidths()
        if preservingVerticalPosition {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: previousVisibleOrigin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        restorePendingMergedSelection()
    }

    private func diffTableView(for plan: RenderPlan) -> NSView {
        let row = NSStackView()
        row.identifier = NSUserInterfaceItemIdentifier("diffTable")
        row.orientation = .horizontal
        row.spacing = 0

        row.addArrangedSubview(pickButtonColumn(for: plan.blockSlots, picksLeft: true))

        let panes = NSStackView()
        panes.orientation = .horizontal
        panes.spacing = 0
        panes.distribution = .fillEqually
        panes.setContentHuggingPriority(.defaultLow, for: .horizontal)
        panes.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for pane in DiffPane.allCases {
            panes.addArrangedSubview(paneColumnView(for: plan, pane: pane))
        }
        row.addArrangedSubview(panes)

        row.addArrangedSubview(pickButtonColumn(for: plan.blockSlots, picksLeft: false))
        return row
    }

    private func pickButtonColumn(for slots: [BlockRenderSlot], picksLeft: Bool) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.spacing = 0
        column.widthAnchor.constraint(equalToConstant: pickButtonSlotWidth).isActive = true

        for slot in slots {
            column.addArrangedSubview(pickButtonSlot(slot.block, picksLeft: picksLeft, rowCount: slot.rowCount))
        }

        return column
    }

    private func pickButtonSlot(_ block: MDBlock, picksLeft: Bool, rowCount: Int) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: CGFloat(rowCount) * lineHeight).isActive = true

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

    private func paneColumnView(for plan: RenderPlan, pane: DiffPane) -> NSView {
        let content = plan.panes[pane] ?? PaneRenderContent()
        let view = PaneColumnView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier(for: pane))
        view.lineHeight = lineHeight
        view.backgroundRuns = content.backgroundRuns
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let layout = NSStackView()
        layout.orientation = .horizontal
        layout.spacing = paneContentSpacing
        layout.alignment = .top
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.setContentHuggingPriority(.defaultLow, for: .horizontal)
        layout.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: paneInset),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -paneInset)
        ])

        if pane != .merged {
            let numbers = NSTextField(labelWithString: "")
            numbers.identifier = NSUserInterfaceItemIdentifier("\(identifier(for: pane))LineNumbers")
            numbers.attributedStringValue = attributedLineNumberText(content.lineNumberLines.joined(separator: "\n"))
            numbers.alignment = .right
            numbers.textColor = .secondaryLabelColor
            numbers.font = lineNumberFont
            numbers.lineBreakMode = .byClipping
            numbers.maximumNumberOfLines = 0
            numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
            layout.addArrangedSubview(numbers)
        }

        let text = content.textLines.joined(separator: "\n")
        let clip = PaneTextClipView(text: text,
                                    pane: pane,
                                    font: paneTextFont,
                                    lineHeight: lineHeight,
                                    isEditable: pane == .merged,
                                    textDelegate: pane == .merged ? self : nil)
        clip.delegate = self
        clip.textOffset = paneStates[pane]?.offset ?? 0
        paneTextClipViews[pane, default: []].append(clip)
        if pane == .merged {
            mergedTextView = clip.editableTextView
        }
        layout.addArrangedSubview(clip)

        return view
    }

    private func renderPlan(for document: MDDocument) -> RenderPlan {
        var panes = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, PaneRenderContent()) })
        var slots = [BlockRenderSlot]()
        var mergedRanges = [MergedBlockTextRange]()
        var totalRows = 0
        var mergedStartLine = 1
        var mergedCharacterLocation = 0
        var mergedHasPreviousLine = false

        for (blockIndex, block) in document.blocks.enumerated() {
            let displayed = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map {
                ($0, displayedLines(for: block, pane: $0, mergedStartLine: mergedStartLine))
            })
            let rowCount = renderRowCount(for: block, displayed: displayed)

            for pane in DiffPane.allCases {
                guard let display = displayed[pane] else { continue }
                var lines = display.lines
                if pane == .merged {
                    lines = mergedContentLines(for: block, lines: lines)
                }
                if lines.count > rowCount {
                    lines = Array(lines.prefix(rowCount))
                }
                if lines.count < rowCount {
                    lines.append(contentsOf: Array(repeating: "", count: rowCount - lines.count))
                }
                if pane == .merged {
                    let rangeStart = mergedCharacterLocation + (mergedHasPreviousLine ? 1 : 0)
                    let rangeLines = block.kind == .changed ? lines : Array(lines.prefix(display.lines.count))
                    mergedRanges.append(MergedBlockTextRange(blockIndex: blockIndex,
                                                             characterRange: NSRange(location: rangeStart,
                                                                                     length: characterLength(for: rangeLines)),
                                                             isEditable: block.kind == .changed))
                    if !lines.isEmpty {
                        if mergedHasPreviousLine {
                            mergedCharacterLocation += 1
                        }
                        mergedCharacterLocation += characterLength(for: lines)
                        mergedHasPreviousLine = true
                    }
                }
                panes[pane]?.textLines.append(contentsOf: lines)
                if pane != .merged {
                    panes[pane]?.lineNumberLines.append(contentsOf: lineNumberLines(lines: display.lines,
                                                                                     start: display.start,
                                                                                     rowCount: rowCount))
                }
                if let color = backgroundColor(for: block, pane: pane) {
                    panes[pane]?.backgroundRuns.append(PaneBackgroundRun(startRow: totalRows,
                                                                         rowCount: rowCount,
                                                                         color: color))
                }
            }

            slots.append(BlockRenderSlot(block: block, rowCount: rowCount))
            totalRows += rowCount
            mergedStartLine += mergedOutputLineCount(for: block)
        }

        if totalRows == 0 {
            for pane in DiffPane.allCases {
                panes[pane]?.textLines.append("")
                if pane != .merged {
                    panes[pane]?.lineNumberLines.append("")
                }
            }
            totalRows = 1
        }

        return RenderPlan(panes: panes, blockSlots: slots, mergedTextRanges: mergedRanges, totalRows: totalRows)
    }

    private func mergedContentLines(for block: MDBlock, lines: [String]) -> [String] {
        if block.kind == .changed && lines.isEmpty {
            return [""]
        }
        return lines
    }

    private func characterLength(for lines: [String]) -> Int {
        guard let first = lines.first else { return 0 }
        return lines.dropFirst().reduce((first as NSString).length) { length, line in
            length + 1 + (line as NSString).length
        }
    }

    private func renderRowCount(for block: MDBlock,
                                displayed: [DiffPane: (lines: [String], start: Int?)]) -> Int {
        max(displayed.values.map(\.lines.count).max() ?? 0, 1)
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
                if block.pick == .unpicked {
                    return NSColor.systemOrange.withAlphaComponent(0.16)
                }
                if block.pick == .manual {
                    return NSColor.systemPurple.withAlphaComponent(0.14)
                }
                return nil
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

    private func lineNumberLines(lines: [String], start: Int?, rowCount: Int) -> [String] {
        guard let start, start > 0 else {
            return Array(repeating: "", count: rowCount)
        }

        return (0..<rowCount).map { index in
            guard index < lines.count, !lines[index].isEmpty else { return "" }
            return "\(start + index)"
        }
    }

    private func attributedLineNumberText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        return NSAttributedString(string: text, attributes: [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ])
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
            case .manual:
                return (block.manualLines ?? [], start)
            case .unpicked:
                return ([], nil)
            @unknown default:
                return ([], nil)
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
            case .manual:
                return block.manualLines?.count ?? 0
            case .unpicked:
                return 0
            @unknown default:
                return 0
        }
    }

    @objc private func pick(_ sender: PickButton) {
        guard let block = sender.block else { return }
        block.pick = sender.picksLeft ? .left : .right
        block.manualLines = []
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

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard textView === mergedTextView else { return true }
        guard let range = mergedTextRange(containing: affectedCharRange), range.isEditable else {
            NSSound.beep()
            return false
        }

        pendingMergedEdit = PendingMergedEdit(blockIndex: range.blockIndex,
                                              oldBlockRange: range.characterRange,
                                              affectedRange: affectedCharRange,
                                              replacement: replacementString ?? "")
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === mergedTextView,
              let edit = pendingMergedEdit else { return }
        pendingMergedEdit = nil

        guard let document, edit.blockIndex < document.blocks.count else {
            updateButtons()
            return
        }

        let replacementLength = (edit.replacement as NSString).length
        let newBlockLength = max(edit.oldBlockRange.length + replacementLength - edit.affectedRange.length, 0)
        let newBlockRange = NSRange(location: edit.oldBlockRange.location, length: newBlockLength)
        let text = textView.string as NSString
        guard NSMaxRange(newBlockRange) <= text.length else {
            updateButtons()
            return
        }

        let block = document.blocks[edit.blockIndex]
        let editedText = text.substring(with: newBlockRange)
        normalize(block: block, editedLines: lines(fromEditedMergedText: editedText))
        preserveSelection(from: textView, blockIndex: edit.blockIndex, blockRange: newBlockRange)
        AppLogger.info("Manually edited changed block left_start=\(block.leftStartLine) right_start=\(block.rightStartLine) pick=\(block.pick.rawValue)")
        render(preservingVerticalPosition: true)
        updateButtons()
    }

    private func mergedTextRange(containing affectedRange: NSRange) -> MergedBlockTextRange? {
        mergedTextRanges.first { range in
            range.isEditable && contains(affectedRange, in: range.characterRange)
        }
    }

    private func contains(_ affectedRange: NSRange, in allowedRange: NSRange) -> Bool {
        let affectedEnd = NSMaxRange(affectedRange)
        let allowedEnd = NSMaxRange(allowedRange)
        if affectedRange.length == 0 {
            return affectedRange.location >= allowedRange.location && affectedRange.location <= allowedEnd
        }
        return affectedRange.location >= allowedRange.location && affectedEnd <= allowedEnd
    }

    private func normalize(block: MDBlock, editedLines: [String]) {
        let leftLines = block.leftLines ?? []
        let rightLines = block.rightLines ?? []
        if editedLines == leftLines {
            block.pick = .left
            block.manualLines = []
        } else if editedLines == rightLines {
            block.pick = .right
            block.manualLines = []
        } else {
            block.pick = .manual
            block.manualLines = editedLines
        }
    }

    private func lines(fromEditedMergedText text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return [] }

        return normalized.components(separatedBy: "\n")
    }

    private func preserveSelection(from textView: NSTextView, blockIndex: Int, blockRange: NSRange) {
        let selection = textView.selectedRange()
        let relativeLocation = min(max(selection.location - blockRange.location, 0), blockRange.length)
        let length = min(selection.length, max(blockRange.length - relativeLocation, 0))
        pendingMergedSelection = PendingMergedSelection(blockIndex: blockIndex,
                                                        relativeLocation: relativeLocation,
                                                        length: length)
    }

    private func restorePendingMergedSelection() {
        guard let selection = pendingMergedSelection else { return }
        pendingMergedSelection = nil
        guard let textView = mergedTextView,
              let range = mergedTextRanges.first(where: { $0.blockIndex == selection.blockIndex }) else { return }

        let relativeLocation = min(selection.relativeLocation, range.characterRange.length)
        let length = min(selection.length, max(range.characterRange.length - relativeLocation, 0))
        let restored = NSRange(location: range.characterRange.location + relativeLocation, length: length)
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(restored)
        textView.scrollRangeToVisible(restored)
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

                var lines = [String]()
                lines.append(contentsOf: block.leftLines ?? [])
                lines.append(contentsOf: block.rightLines ?? [])
                lines.append(contentsOf: block.manualLines ?? [])
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
