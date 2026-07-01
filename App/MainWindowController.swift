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
         textDelegate: NSTextViewDelegate? = nil,
         undoHandler: (() -> Void)? = nil,
         redoHandler: (() -> Void)? = nil) {
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
        let blockIndexes: [Int]
        let oldUnionRange: NSRange
        let affectedRange: NSRange
        let replacement: String
        let undoSelection: PendingMergedSelection
    }

    private struct PendingMergedSelection {
        let blockIndex: Int
        let relativeLocation: Int
        let length: Int
    }

    private struct MergedBlockSnapshot {
        let blockIndex: Int
        let pick: MDPickSide
        let manualLines: [String]
    }

    private struct TimedPhase {
        let name: String
        let milliseconds: Double
    }

    private enum SaveTarget {
        case savePanel
        case gitWorktreeFile(repositoryRoot: URL, relativePath: String)
        case mergeToolOutput(URL)
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
    private let gitFilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gitStatusLabel = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let horizontalScrollerRow = NSStackView()
    private let paneScrollerStack = NSStackView()
    private let mergeUndoManager: UndoManager = {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }()

    private var leftURL: URL?
    private var rightURL: URL?
    private var document: MDDocument?
    private var saveTarget = SaveTarget.savePanel
    private var gitRepositoryRoot: URL?
    private var gitConflictFiles = [MDGitConflictFile]()
    private var selectedGitConflictIndex: Int?
    private var gitResolvedPaths = Set<String>()
    private var paneScrollers = [DiffPane: PaneHorizontalSlider]()
    private var paneStates = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, PaneHorizontalState()) })
    private var paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
    private weak var mergedTextView: NSTextView?
    private var mergedTextRanges = [MergedBlockTextRange]()
    private var pendingMergedEdit: PendingMergedEdit?
    private var pendingMergedSelection: PendingMergedSelection?
    private var sharedHorizontalValue: Double = 0
    var mergeToolCompletionHandler: ((Bool) -> Void)?

    private var lineHeight: CGFloat {
        ceil(paneTextFont.ascender - paneTextFont.descender + paneTextFont.leading)
    }

    override func loadView() {
        AppLogger.info("Loading main view.")
        view = NSView()

        gitFilePopup.identifier = NSUserInterfaceItemIdentifier("gitConflictFilePopup")
        gitStatusLabel.identifier = NSUserInterfaceItemIdentifier("gitStatusLabel")
        gitStatusLabel.textColor = .secondaryLabelColor
        gitStatusLabel.lineBreakMode = .byTruncatingMiddle
        gitStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gitStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [leftButton, rightButton, compareButton, gitFilePopup, gitStatusLabel, saveButton])
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
        gitFilePopup.target = self; gitFilePopup.action = #selector(selectGitConflictFile(_:))
        updateButtons()
        AppLogger.info("Main view loaded.")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshPaneViewportWidths()
    }

    func load(left: URL, right: URL) {
        AppLogger.info("Received files to load left=\(left.path) right=\(right.path)")
        resetGitSession()
        saveTarget = .savePanel
        leftURL = left
        rightURL = right
        compare()
    }

    func loadGit(startPath: URL) {
        AppLogger.info("Received git session start_path=\(startPath.path)")
        resetGitSession()
        document = nil
        leftURL = nil
        rightURL = nil
        saveTarget = .savePanel
        resetEditorStateAfterDocumentLoad()

        var error: NSError?
        var phases = [TimedPhase]()
        let (discoveredRootPath, discoverPhase) = timed("discoverRepo") {
            MDGitDiscoverRepository(startPath.path, &error)
        }
        phases.append(discoverPhase)
        guard let rootPath = discoveredRootPath else {
            logPerformance("loadGit", phases: phases, metadata: "failed=discover", minimumTotalMilliseconds: 0)
            show(error?.localizedDescription ?? "No git repository found.")
            updateButtons()
            return
        }

        let (discoveredFiles, listPhase) = timed("listConflicts") {
            MDGitConflictFiles(rootPath, &error)
        }
        phases.append(listPhase)
        guard let files = discoveredFiles else {
            logPerformance("loadGit", phases: phases, metadata: "failed=list", minimumTotalMilliseconds: 0)
            show(error?.localizedDescription ?? "Could not read git conflicts.")
            updateButtons()
            return
        }
        logPerformance("loadGit", phases: phases, metadata: "files=\(files.count)", minimumTotalMilliseconds: 0)

        gitRepositoryRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
        gitConflictFiles = files
        if gitConflictFiles.isEmpty {
            document = nil
            gitStatusLabel.stringValue = "No conflicted files found."
            render(preservingVerticalPosition: false)
            updateButtons()
            return
        }

        updateGitControls()
        loadGitConflictFile(at: 0)
    }

    func loadGitMergeTool(base: URL, local: URL, remote: URL, merged: URL) {
        AppLogger.info("Received git mergetool base=\(base.path) local=\(local.path) remote=\(remote.path) merged=\(merged.path)")
        resetGitSession()
        document = nil
        leftURL = nil
        rightURL = nil
        saveTarget = .mergeToolOutput(merged)
        gitStatusLabel.stringValue = "Resolving \(merged.lastPathComponent)"
        resetEditorStateAfterDocumentLoad()

        do {
            var phases = try loadConflictDocument(from: merged)
            phases.append(timed("render") { resetEditorStateAfterDocumentLoad() }.1)
            phases.append(timed("updateButtons") { updateButtons() }.1)
            logPerformance("loadMergeTool", phases: phases, metadata: "path=\(merged.path)", minimumTotalMilliseconds: 0)
        } catch {
            AppLogger.error("Git mergetool load failed: \(error.localizedDescription)")
            show(error.localizedDescription)
            updateButtons()
        }
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
        resetGitSession()
        saveTarget = .savePanel
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
            resetEditorStateAfterDocumentLoad()
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
            var phases = [TimedPhase]()
            let (text, mergePhase) = try timed("mergedText") { try document.mergedText() }
            phases.append(mergePhase)
            switch saveTarget {
                case .savePanel:
                    let panel = NSSavePanel()
                    if panel.runModal() == .OK, let url = panel.url {
                        phases.append(try timed("writeFile") {
                            try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                        }.1)
                        logPerformance("savePanel",
                                       phases: phases,
                                       metadata: "path=\(url.path) bytes=\(text.utf8.count)",
                                       minimumTotalMilliseconds: 0)
                        AppLogger.info("Saved merged text to \(url.path) bytes=\(text.utf8.count)")
                    } else {
                        AppLogger.info("Save panel cancelled.")
                    }
                case let .gitWorktreeFile(repositoryRoot, relativePath):
                    let url = repositoryRoot.appendingPathComponent(relativePath)
                    phases.append(try timed("writeFile") {
                        try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                    }.1)
                    var stageError: NSError?
                    let (staged, stagePhase) = timed("gitStage") {
                        MDGitStageFile(repositoryRoot.path, relativePath, &stageError)
                    }
                    phases.append(stagePhase)
                    guard staged else {
                        logPerformance("saveGit",
                                       phases: phases,
                                       metadata: "path=\(relativePath) bytes=\(text.utf8.count) failed=stage",
                                       minimumTotalMilliseconds: 0)
                        throw stageError ?? NSError(domain: "mcdiff", code: 6, userInfo: [
                            NSLocalizedDescriptionKey: "Could not stage resolved file."
                        ])
                    }
                    gitResolvedPaths.insert(relativePath)
                    AppLogger.info("Saved and staged git file relative_path=\(relativePath) bytes=\(text.utf8.count)")
                    phases.append(timed("updateGitControls") { updateGitControls() }.1)
                    if let nextIndex = nextUnresolvedGitConflictIndex(after: selectedGitConflictIndex) {
                        phases.append(timed("loadNextConflict") { loadGitConflictFile(at: nextIndex) }.1)
                    } else {
                        gitStatusLabel.stringValue = "All conflicts saved and staged."
                    }
                    logPerformance("saveGit",
                                   phases: phases,
                                   metadata: "path=\(relativePath) bytes=\(text.utf8.count)",
                                   minimumTotalMilliseconds: 0)
                case let .mergeToolOutput(url):
                    phases.append(try timed("writeFile") {
                        try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                    }.1)
                    logPerformance("saveMergeTool",
                                   phases: phases,
                                   metadata: "path=\(url.path) bytes=\(text.utf8.count)",
                                   minimumTotalMilliseconds: 0)
                    AppLogger.info("Saved git mergetool output to \(url.path) bytes=\(text.utf8.count)")
                    mergeToolCompletionHandler?(true)
            }
        } catch {
            AppLogger.error("Save failed: \(error.localizedDescription)")
            show(error.localizedDescription)
        }
        updateButtons()
    }

    private func render(preservingVerticalPosition: Bool) {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        var phases = [TimedPhase]()
        phases.append(timed("contentWidths") { updatePaneContentWidths() }.1)
        phases.append(timed("clearViews") {
            paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
            mergedTextView = nil
            mergedTextRanges = []
            stack.arrangedSubviews.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }.1)
        guard let document else {
            logPerformance("render", phases: phases, metadata: "document=none", minimumTotalMilliseconds: 75)
            return
        }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        let (plan, planPhase) = timed("renderPlan") { renderPlan(for: document) }
        phases.append(planPhase)
        mergedTextRanges = plan.mergedTextRanges
        let (_, tablePhase) = timed("views") { stack.addArrangedSubview(diffTableView(for: plan)) }
        phases.append(tablePhase)
        phases.append(timed("refreshWidths") { refreshPaneViewportWidths() }.1)
        if preservingVerticalPosition {
            phases.append(timed("restoreScroll") {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: previousVisibleOrigin.y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }.1)
        }
        phases.append(timed("restoreSelection") { restorePendingMergedSelection() }.1)
        logPerformance("render",
                       phases: phases,
                       metadata: "blocks=\(document.blocks.count) rows=\(plan.totalRows) preserving=\(preservingVerticalPosition)",
                       minimumTotalMilliseconds: 75)
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
                                    textDelegate: pane == .merged ? self : nil,
                                    undoHandler: { [weak self] in self?.performUndo() },
                                    redoHandler: { [weak self] in self?.performRedo() })
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
                                                             isEditable: true))
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
            if block.pick == .manual {
                return (block.manualLines ?? [], start)
            }
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
            if block.pick == .manual {
                return block.manualLines?.count ?? 0
            }
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
        if let blockIndex = document?.blocks.firstIndex(where: { $0 === block }) {
            registerMergedUndo(before: snapshots(for: [blockIndex]),
                               actionName: sender.picksLeft ? "Use Left" : "Use Right",
                               restoreSelection: currentMergedSelection(affecting: [blockIndex]))
        }
        block.pick = sender.picksLeft ? .left : .right
        block.manualLines = []
        AppLogger.info("Picked \(sender.picksLeft ? "left" : "right") for changed block left_start=\(block.leftStartLine) right_start=\(block.rightStartLine)")
        render(preservingVerticalPosition: true)
        updateButtons()
    }

    @objc func undo(_ sender: Any?) {
        performUndo()
    }

    @objc func redo(_ sender: Any?) {
        performRedo()
    }

    private func performUndo() {
        guard mergeUndoManager.canUndo else {
            NSSound.beep()
            return
        }

        mergeUndoManager.undo()
    }

    private func performRedo() {
        guard mergeUndoManager.canRedo else {
            NSSound.beep()
            return
        }

        mergeUndoManager.redo()
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
        let ranges = mergedTextRanges(affectedBy: affectedCharRange)
        guard let firstRange = ranges.first, let lastRange = ranges.last else {
            NSSound.beep()
            return false
        }

        let affectedEnd = NSMaxRange(affectedCharRange)
        let unionStart = min(firstRange.characterRange.location, affectedCharRange.location)
        let unionEnd = max(NSMaxRange(lastRange.characterRange), affectedEnd)
        pendingMergedEdit = PendingMergedEdit(blockIndexes: ranges.map(\.blockIndex),
                                              oldUnionRange: NSRange(location: unionStart,
                                                                     length: max(unionEnd - unionStart, 0)),
                                              affectedRange: affectedCharRange,
                                              replacement: replacementString ?? "",
                                              undoSelection: pendingSelection(from: affectedCharRange,
                                                                              blockIndex: firstRange.blockIndex,
                                                                              blockRange: firstRange.characterRange))
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === mergedTextView,
              let edit = pendingMergedEdit else { return }
        let editStart = DispatchTime.now().uptimeNanoseconds
        pendingMergedEdit = nil

        guard let document, let firstBlockIndex = edit.blockIndexes.first, firstBlockIndex < document.blocks.count else {
            updateButtons()
            return
        }

        let replacementLength = (edit.replacement as NSString).length
        let newBlockLength = max(edit.oldUnionRange.length + replacementLength - edit.affectedRange.length, 0)
        let newBlockRange = NSRange(location: edit.oldUnionRange.location, length: newBlockLength)
        let text = textView.string as NSString
        guard NSMaxRange(newBlockRange) <= text.length else {
            updateButtons()
            return
        }

        let editedText = text.substring(with: newBlockRange)
        let editedLines = lines(fromEditedMergedText: editedText)
        let beforeSnapshots = snapshots(for: edit.blockIndexes)
        let beforeLineCounts = Dictionary(uniqueKeysWithValues: edit.blockIndexes.compactMap { blockIndex -> (Int, Int)? in
            guard blockIndex >= 0 && blockIndex < document.blocks.count else { return nil }
            return (blockIndex, mergedOutputLineCount(for: document.blocks[blockIndex]))
        })
        for (offset, blockIndex) in edit.blockIndexes.enumerated() where blockIndex < document.blocks.count {
            normalize(block: document.blocks[blockIndex], editedLines: offset == 0 ? editedLines : [])
        }
        registerMergedUndo(before: beforeSnapshots, actionName: "Edit", restoreSelection: edit.undoSelection)
        pendingMergedSelection = pendingSelection(from: textView.selectedRange(),
                                                  blockIndex: firstBlockIndex,
                                                  blockRange: newBlockRange)
        let shouldRender = mergedEditNeedsRender(edit: edit,
                                                 beforeSnapshots: beforeSnapshots,
                                                 beforeLineCounts: beforeLineCounts,
                                                 editedLines: editedLines)
        if shouldRender {
            render(preservingVerticalPosition: true)
        } else {
            updateMergedTextRangesAfterInlineEdit(blockIndex: firstBlockIndex, newBlockRange: newBlockRange)
        }
        updateButtons()
        let elapsed = DispatchTime.now().uptimeNanoseconds - editStart
        logPerformance("edit",
                       phases: [TimedPhase(name: "total", milliseconds: Double(elapsed) / 1_000_000.0)],
                       metadata: "affectedBlocks=\(edit.blockIndexes.count) replacementLength=\(replacementLength) newBlockLength=\(newBlockLength) blocks=\(document.blocks.count) rendered=\(shouldRender)",
                       minimumTotalMilliseconds: 50)
    }

    private func mergedEditNeedsRender(edit: PendingMergedEdit,
                                       beforeSnapshots: [MergedBlockSnapshot],
                                       beforeLineCounts: [Int: Int],
                                       editedLines: [String]) -> Bool {
        guard edit.blockIndexes.count == 1,
              let blockIndex = edit.blockIndexes.first,
              let document,
              blockIndex >= 0,
              blockIndex < document.blocks.count else {
            return true
        }

        let block = document.blocks[blockIndex]
        if beforeLineCounts[blockIndex] != mergedOutputLineCount(for: block) {
            return true
        }

        if let before = beforeSnapshots.first(where: { $0.blockIndex == blockIndex }),
           before.pick != block.pick {
            return true
        }

        let maxEditedWidth = editedLines.map(measuredLineWidth).max() ?? 0
        if maxEditedWidth > sharedMaxContentWidth() + 1 {
            return true
        }

        return false
    }

    private func updateMergedTextRangesAfterInlineEdit(blockIndex: Int, newBlockRange: NSRange) {
        guard let rangeIndex = mergedTextRanges.firstIndex(where: { $0.blockIndex == blockIndex }) else { return }

        let oldRange = mergedTextRanges[rangeIndex]
        let delta = newBlockRange.length - oldRange.characterRange.length
        mergedTextRanges[rangeIndex] = MergedBlockTextRange(blockIndex: oldRange.blockIndex,
                                                            characterRange: newBlockRange,
                                                            isEditable: oldRange.isEditable)
        guard delta != 0, rangeIndex + 1 < mergedTextRanges.count else { return }

        for index in (rangeIndex + 1)..<mergedTextRanges.count {
            let range = mergedTextRanges[index]
            mergedTextRanges[index] = MergedBlockTextRange(blockIndex: range.blockIndex,
                                                           characterRange: NSRange(location: range.characterRange.location + delta,
                                                                                   length: range.characterRange.length),
                                                           isEditable: range.isEditable)
        }
    }

    private func snapshots(for blockIndexes: [Int]) -> [MergedBlockSnapshot] {
        guard let document else { return [] }
        var seen = Set<Int>()
        var snapshots = [MergedBlockSnapshot]()
        for blockIndex in blockIndexes where blockIndex >= 0 && blockIndex < document.blocks.count && !seen.contains(blockIndex) {
            seen.insert(blockIndex)
            let block = document.blocks[blockIndex]
            snapshots.append(MergedBlockSnapshot(blockIndex: blockIndex,
                                                 pick: block.pick,
                                                 manualLines: block.manualLines ?? []))
        }
        return snapshots
    }

    private func apply(snapshots: [MergedBlockSnapshot]) {
        guard let document else { return }
        for snapshot in snapshots where snapshot.blockIndex >= 0 && snapshot.blockIndex < document.blocks.count {
            let block = document.blocks[snapshot.blockIndex]
            block.pick = snapshot.pick
            block.manualLines = snapshot.manualLines
        }
    }

    private func registerMergedUndo(before snapshots: [MergedBlockSnapshot],
                                    actionName: String,
                                    restoreSelection: PendingMergedSelection?) {
        guard !snapshots.isEmpty else { return }

        mergeUndoManager.beginUndoGrouping()
        mergeUndoManager.registerUndo(withTarget: self) { target in
            target.restoreMergedSnapshots(snapshots,
                                          actionName: actionName,
                                          restoreSelection: restoreSelection)
        }
        mergeUndoManager.setActionName(actionName)
        mergeUndoManager.endUndoGrouping()
    }

    private func restoreMergedSnapshots(_ snapshots: [MergedBlockSnapshot],
                                        actionName: String,
                                        restoreSelection: PendingMergedSelection?) {
        let blockIndexes = snapshots.map(\.blockIndex)
        let redoSnapshots = self.snapshots(for: blockIndexes)
        let redoSelection = currentMergedSelection(affecting: Set(blockIndexes))
        apply(snapshots: snapshots)
        pendingMergedSelection = restoreSelection ?? redoSelection
        AppLogger.info("Restored merged edit state action=\(actionName) affected_blocks=\(snapshots.count)")
        render(preservingVerticalPosition: true)
        updateButtons()
        registerMergedUndo(before: redoSnapshots,
                           actionName: actionName,
                           restoreSelection: redoSelection)
    }

    private func mergedTextRanges(affectedBy affectedRange: NSRange) -> [MergedBlockTextRange] {
        guard !mergedTextRanges.isEmpty else { return [] }
        let startIndex = mergedTextRangeIndex(at: affectedRange.location)
        let endLocation = affectedRange.length == 0 ? affectedRange.location : max(NSMaxRange(affectedRange) - 1, affectedRange.location)
        let endIndex = mergedTextRangeIndex(at: endLocation)
        guard let startIndex, let endIndex else { return [] }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        return Array(mergedTextRanges[lower...upper]).filter(\.isEditable)
    }

    private func mergedTextRangeIndex(at location: Int) -> Int? {
        for (index, range) in mergedTextRanges.enumerated() {
            let start = range.characterRange.location
            let end = NSMaxRange(range.characterRange)

            if range.characterRange.length == 0, location == start {
                return index
            }

            if location >= start && location < end {
                return index
            }

            if location == end {
                let nextStart = index + 1 < mergedTextRanges.count ? mergedTextRanges[index + 1].characterRange.location : nil
                if nextStart == nil || location < nextStart! {
                    return index
                }
            }
        }

        guard let last = mergedTextRanges.last, location >= NSMaxRange(last.characterRange) else {
            return nil
        }
        return mergedTextRanges.indices.last
    }

    private func normalize(block: MDBlock, editedLines: [String]) {
        let leftLines = block.leftLines ?? []
        let rightLines = block.rightLines ?? []
        if block.kind == .equal {
            if editedLines == leftLines {
                block.pick = .unpicked
                block.manualLines = []
            } else {
                block.pick = .manual
                block.manualLines = editedLines
            }
            return
        }

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

    private func currentMergedSelection(affecting blockIndexes: Set<Int>) -> PendingMergedSelection? {
        guard let textView = mergedTextView else { return nil }
        guard let rangeIndex = mergedTextRangeIndex(at: textView.selectedRange().location) else { return nil }
        let range = mergedTextRanges[rangeIndex]
        guard blockIndexes.contains(range.blockIndex) else { return nil }
        return pendingSelection(from: textView.selectedRange(),
                                blockIndex: range.blockIndex,
                                blockRange: range.characterRange)
    }

    private func pendingSelection(from selection: NSRange,
                                  blockIndex: Int,
                                  blockRange: NSRange) -> PendingMergedSelection {
        let relativeLocation = min(max(selection.location - blockRange.location, 0), blockRange.length)
        let length = min(selection.length, max(blockRange.length - relativeLocation, 0))
        return PendingMergedSelection(blockIndex: blockIndex,
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

    @objc private func selectGitConflictFile(_ sender: NSPopUpButton) {
        loadGitConflictFile(at: sender.indexOfSelectedItem)
    }

    private func loadGitConflictFile(at index: Int) {
        guard index >= 0, index < gitConflictFiles.count, let gitRepositoryRoot else { return }

        selectedGitConflictIndex = index
        let file = gitConflictFiles[index]
        let relativePath = file.relativePath ?? ""
        let message = file.message ?? ""
        var phases = [TimedPhase]()
        phases.append(timed("updateGitControls") { updateGitControls() }.1)

        guard file.isTextConflict else {
            document = nil
            saveTarget = .savePanel
            gitStatusLabel.stringValue = message.isEmpty ? "Unsupported conflict: \(relativePath)" : message
            resetEditorStateAfterDocumentLoad()
            updateButtons()
            return
        }

        let url = gitRepositoryRoot.appendingPathComponent(relativePath)
        saveTarget = .gitWorktreeFile(repositoryRoot: gitRepositoryRoot, relativePath: relativePath)
        gitStatusLabel.stringValue = gitResolvedPaths.contains(relativePath)
            ? "Saved and staged: \(relativePath)"
            : "Resolving \(relativePath)"

        do {
            phases.append(contentsOf: try loadConflictDocument(from: url))
            phases.append(timed("render") { resetEditorStateAfterDocumentLoad() }.1)
            logPerformance("loadGitConflictFile",
                           phases: phases,
                           metadata: "path=\(relativePath)",
                           minimumTotalMilliseconds: 0)
        } catch {
            AppLogger.error("Git conflict load failed: \(error.localizedDescription)")
            document = nil
            gitStatusLabel.stringValue = "Could not load \(relativePath)"
            render(preservingVerticalPosition: false)
            show(error.localizedDescription)
        }
        updateButtons()
    }

    private func loadConflictDocument(from url: URL) throws -> [TimedPhase] {
        var phases = [TimedPhase]()
        let text: String
        let readPhase: TimedPhase
        do {
            (text, readPhase) = try timed("readFile") {
                try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            throw NSError(domain: "mcdiff", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not read \(url.path) as UTF-8 text. Binary conflicts are not supported yet."
            ])
        }
        phases.append(readPhase)

        var error: NSError?
        let (parsedDocument, parsePhase) = timed("parseConflict") {
            MDMakeConflictDocument(text, &error)
        }
        phases.append(parsePhase)
        guard let parsed = parsedDocument else {
            throw error ?? NSError(domain: "mcdiff", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse conflict markers."
            ])
        }
        guard parsed.blocks.contains(where: { $0.kind == .changed }) else {
            throw NSError(domain: "mcdiff", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No conflict markers found in \(url.path)."
            ])
        }
        document = parsed
        return phases
    }

    private func resetGitSession() {
        gitRepositoryRoot = nil
        gitConflictFiles = []
        selectedGitConflictIndex = nil
        gitResolvedPaths = []
        gitFilePopup.removeAllItems()
        gitStatusLabel.stringValue = ""
    }

    private func resetEditorStateAfterDocumentLoad() {
        pendingMergedEdit = nil
        pendingMergedSelection = nil
        mergeUndoManager.removeAllActions(withTarget: self)
        resetHorizontalOffsets()
        render(preservingVerticalPosition: false)
    }

    private func updateGitControls() {
        gitFilePopup.removeAllItems()
        for file in gitConflictFiles {
            gitFilePopup.addItem(withTitle: gitFileTitle(for: file))
        }
        if let selectedGitConflictIndex, selectedGitConflictIndex >= 0, selectedGitConflictIndex < gitConflictFiles.count {
            gitFilePopup.selectItem(at: selectedGitConflictIndex)
        }
    }

    private func gitFileTitle(for file: MDGitConflictFile) -> String {
        let relativePath = file.relativePath ?? ""
        if gitResolvedPaths.contains(relativePath) {
            return "[saved] \(relativePath)"
        }
        if !file.isTextConflict {
            return "[unsupported] \(relativePath)"
        }
        return relativePath
    }

    private func nextUnresolvedGitConflictIndex(after currentIndex: Int?) -> Int? {
        guard !gitConflictFiles.isEmpty else { return nil }
        let start = ((currentIndex ?? -1) + 1) % gitConflictFiles.count
        for offset in 0..<gitConflictFiles.count {
            let index = (start + offset) % gitConflictFiles.count
            let file = gitConflictFiles[index]
            if file.isTextConflict && !gitResolvedPaths.contains(file.relativePath ?? "") {
                return index
            }
        }
        return nil
    }

    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func updateButtons() {
        let isGitRepositoryMode = gitRepositoryRoot != nil
        let isMergeToolMode: Bool
        if case .mergeToolOutput = saveTarget {
            isMergeToolMode = true
        } else {
            isMergeToolMode = false
        }

        leftButton.isHidden = isGitRepositoryMode || isMergeToolMode
        rightButton.isHidden = isGitRepositoryMode || isMergeToolMode
        compareButton.isHidden = isGitRepositoryMode || isMergeToolMode
        gitFilePopup.isHidden = !isGitRepositoryMode
        gitStatusLabel.isHidden = !isGitRepositoryMode && !isMergeToolMode

        compareButton.isEnabled = !isGitRepositoryMode && !isMergeToolMode && leftURL != nil && rightURL != nil

        let canSaveDocument = document?.canSave() == true
        switch saveTarget {
            case .savePanel:
                saveButton.title = isGitRepositoryMode ? "Save and Stage" : "Save Result"
                saveButton.isEnabled = canSaveDocument
            case let .gitWorktreeFile(_, relativePath):
                saveButton.title = "Save and Stage"
                saveButton.isEnabled = canSaveDocument && !gitResolvedPaths.contains(relativePath)
            case .mergeToolOutput:
                saveButton.title = "Save Merge"
                saveButton.isEnabled = canSaveDocument
        }
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
                    if block.pick == .manual {
                        return block.manualLines ?? []
                    }
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

    private func sharedMaxContentWidth() -> CGFloat {
        paneStates.values.map(\.contentWidth).max() ?? 0
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

    private func timed<T>(_ name: String, _ work: () throws -> T) rethrows -> (T, TimedPhase) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try work()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return (result, TimedPhase(name: name, milliseconds: Double(elapsed) / 1_000_000.0))
    }

    private func logPerformance(_ operation: String,
                                phases: [TimedPhase],
                                metadata: String = "",
                                minimumTotalMilliseconds: Double = 0) {
        let total = phases.reduce(0) { $0 + $1.milliseconds }
        guard total >= minimumTotalMilliseconds else { return }

        let phaseText = phases
            .map { "\($0.name)=\(String(format: "%.1f", $0.milliseconds))ms" }
            .joined(separator: " ")
        let metadataText = metadata.isEmpty ? "" : " \(metadata)"
        AppLogger.info("PERF \(operation) total=\(String(format: "%.1f", total))ms\(metadataText) \(phaseText)")
    }
}
