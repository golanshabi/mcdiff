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

private final class PaneTextClipView: NSView {
    let pane: DiffPane
    private let label: NSTextField
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
        let labelSize = label.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(labelSize.height, 1))
    }

    init(text: String, pane: DiffPane, font: NSFont) {
        self.pane = pane
        label = NSTextField(labelWithString: text.isEmpty ? " " : text)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)TextClip")
        wantsLayer = true
        layer?.masksToBounds = true
        label.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)Text")
        label.font = font
        label.lineBreakMode = .byClipping
        addSubview(label)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("PaneTextClipView does not support storyboards")
    }

    override func layout() {
        super.layout()
        let labelSize = label.intrinsicContentSize
        let labelWidth = max(labelSize.width, bounds.width + textOffset)
        let labelHeight = max(labelSize.height, bounds.height)
        label.frame = NSRect(x: -textOffset, y: 0, width: labelWidth, height: labelHeight)
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        if abs(deltaX) > abs(event.scrollingDeltaY), abs(deltaX) > 0 {
            delegate?.paneTextClipView(self, didScrollHorizontallyBy: deltaX)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

final class MainWindowController: NSViewController, PaneTextClipViewDelegate {
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
        let clip = PaneTextClipView(text: text, pane: pane, font: paneTextFont)
        clip.delegate = self
        clip.textOffset = paneStates[pane]?.offset ?? 0
        paneTextClipViews[pane, default: []].append(clip)
        content.addArrangedSubview(clip)

        view.addArrangedSubview(content)
        return view
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
