import AppKit

final class MainWindowController: NSViewController, PaneTextClipViewDelegate, NSTextViewDelegate {
    struct PaneRenderContent {
        var textLines = [String]()
        var lineNumberLines = [String]()
        var lineNumberControls = [Int: PaneLineNumberControl]()
        var backgroundRuns = [PaneBackgroundRun]()
    }

    struct PaneDisplay {
        let lines: [String]
        let start: Int?
        let lineNumberLines: [String]?
        let lineNumberControls: [Int: PaneLineNumberControl]
        let mergedRangeSegments: [MergedRangeSegment]
        let isEditable: Bool
        let collapsedRowRanges: [NSRange]
    }

    struct MergedRangeSegment {
        let rowRange: NSRange
        let isEditable: Bool
        let sourceLineRange: NSRange?
    }

    struct CompactContextExpansion {
        var prefixLineCount: Int
        var suffixLineCount: Int
    }

    struct BlockRenderSlot {
        let block: MDBlock
        let rowCount: Int
    }

    struct BlockRenderRows {
        let startRow: Int
        let rowCount: Int
    }

    struct RenderPlan {
        var panes: [DiffPane: PaneRenderContent]
        var visiblePanes: [DiffPane]
        var blockSlots: [BlockRenderSlot]
        var blockRows: [Int: BlockRenderRows]
        var mergedTextRanges: [MergedBlockTextRange]
        var totalRows: Int
    }

    struct MergedBlockTextRange {
        let blockIndex: Int
        let characterRange: NSRange
        let isEditable: Bool
        let sourceLineRange: NSRange?
    }

    struct PendingMergedEdit {
        let ranges: [MergedBlockTextRange]
        let blockIndexes: [Int]
        let oldUnionRange: NSRange
        let affectedRange: NSRange
        let replacement: String
        let undoSelection: PendingMergedSelection
    }

    struct PendingMergedSelection {
        let blockIndex: Int
        let sourceLineRange: NSRange?
        let sourceLineLocation: Int?
        let sourceColumn: Int?
        let relativeLocation: Int
        let length: Int
    }

    struct MergedBlockSnapshot {
        let blockIndex: Int
        let pick: MDPickSide
        let manualLines: [String]
    }

    struct TimedPhase {
        let name: String
        let milliseconds: Double
    }

    enum SaveTarget {
        case savePanel
        case gitWorktreeFile(repositoryRoot: URL, relativePath: String)
        case gitDiffPreview
        case mergeToolOutput(URL)
    }

    let paneTextFont = NSFont.monospacedSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
    let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    let pickButtonFont = NSFont.systemFont(ofSize: 18, weight: .medium)
    let pickButtonBaselineOffset: CGFloat = -2
    let pickButtonSlotWidth: CGFloat = 44
    let lineNumberWidth: CGFloat = 42
    let paneInset: CGFloat = 8
    let paneContentSpacing: CGFloat = 8
    let horizontalScrollerHeight: CGFloat = 22
    let horizontalWheelSensitivity: CGFloat = 3
    let gitFileBrowserDefaultWidth: CGFloat = 280
    let gitFileBrowserCollapsedWidth: CGFloat = 38
    let gitFileBrowserMinimumWidth: CGFloat = 150
    let gitFileBrowserMaximumWidth: CGFloat = 520
    let gitFileBrowserResizeHandleWidth: CGFloat = 6
    let gitContextLineCount = 20
    let gitContextExpansionLineCount = 5
    let markerlessConflictErrorCode = 8
    let markerlessConflictMessage = "file has no conflicts but is unmerged"

    let leftButton = NSButton(title: "Choose Left File", target: nil, action: nil)
    let rightButton = NSButton(title: "Choose Right File", target: nil, action: nil)
    let compareButton = NSButton(title: "Compare", target: nil, action: nil)
    let saveButton = NSButton(title: "Save Result", target: nil, action: nil)
    let gitFilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let gitStatusLabel = NSTextField(labelWithString: "")
    let gitFileBrowserColumn = NSStackView()
    let gitFileBrowserToggleRow = NSStackView()
    let gitFileBrowserToggleButton = NSButton()
    let gitFileBrowserPanel = NSStackView()
    let gitFileSearchField = NSSearchField()
    let gitFileBrowserScroll = NSScrollView()
    let gitFileOutline = NSOutlineView()
    let gitFileBrowserResizeHandle = SidebarResizeHandle()
    let scroll = TimedScrollView()
    let stack = NSStackView()
    let horizontalScrollerRow = NSStackView()
    let paneScrollerStack = NSStackView()
    let mergeUndoManager: UndoManager = {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }()

    var leftURL: URL?
    var rightURL: URL?
    var document: MDDocument?
    var saveTarget = SaveTarget.savePanel
    var gitRepositoryRoot: URL?
    var gitConflictFiles = [MDGitConflictFile]()
    var gitFileBrowserNodes = [GitFileBrowserNode]()
    var selectedGitConflictIndex: Int?
    var gitResolvedPaths = Set<String>()
    var isReloadingGitFileBrowser = false
    var isGitFileBrowserHidden = false
    var gitFileBrowserLastVisibleWidth: CGFloat = 280
    var gitFileBrowserWidthConstraint: NSLayoutConstraint?
    var paneSyntaxFileNames = [DiffPane: String]()
    var pendingMergedSyntaxRefresh: DispatchWorkItem?
    var paneScrollers = [DiffPane: PaneHorizontalSlider]()
    var paneScrollerSpacers = [DiffPane: NSView]()
    var visibleRenderPanes = DiffPane.allCases
    var paneStates = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, PaneHorizontalState()) })
    var paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
    var paneColumnViews = [DiffPane: PaneColumnView]()
    var paneLineNumberViews = [DiffPane: NSView]()
    var renderedBlockRows = [Int: BlockRenderRows]()
    var compactContextExpansions = [Int: CompactContextExpansion]()
    weak var mergedTextView: NSTextView?
    var mergedTextRanges = [MergedBlockTextRange]()
    var pendingMergedEdit: PendingMergedEdit?
    var pendingMergedSelection: PendingMergedSelection?
    var sharedHorizontalValue: Double = 0
    var mergeToolCompletionHandler: ((Bool) -> Void)?

    var lineHeight: CGFloat {
        ceil(paneTextFont.ascender - paneTextFont.descender + paneTextFont.leading)
    }

    var rendersConflictContextOnly: Bool {
        switch saveTarget {
            case .gitWorktreeFile, .mergeToolOutput:
                return true
            case .savePanel, .gitDiffPreview:
                return false
        }
    }

    var rendersUnchangedContextCompactly: Bool {
        switch saveTarget {
            case .gitWorktreeFile, .mergeToolOutput, .gitDiffPreview:
                return true
            case .savePanel:
                return false
        }
    }

    var isGitDiffPreview: Bool {
        if case .gitDiffPreview = saveTarget {
            return true
        }
        return false
    }

    var panesForCurrentRender: [DiffPane] {
        isGitDiffPreview ? [.left, .right] : DiffPane.allCases
    }

    override func loadView() {
        AppLogger.info("Loading main view.")
        view = NSView()
        scroll.performanceLogger = { [weak self] operation, milliseconds, metadata in
            self?.logInputPerformance(operation, milliseconds: milliseconds, metadata: metadata)
        }

        gitFilePopup.identifier = NSUserInterfaceItemIdentifier("gitConflictFilePopup")
        gitFilePopup.isHidden = true
        gitStatusLabel.identifier = NSUserInterfaceItemIdentifier("gitStatusLabel")
        gitStatusLabel.textColor = .secondaryLabelColor
        gitStatusLabel.lineBreakMode = .byTruncatingMiddle
        gitStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gitStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gitFileBrowserLastVisibleWidth = gitFileBrowserDefaultWidth
        configureGitFileBrowserControls()

        let bar = NSStackView(views: [leftButton,
                                      rightButton,
                                      compareButton,
                                      gitFilePopup,
                                      gitStatusLabel,
                                      saveButton])
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
        configureGitFileBrowser()

        let editorStack = NSStackView(views: [scroll, horizontalScrollerRow])
        editorStack.orientation = .vertical
        editorStack.spacing = 0
        editorStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        editorStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        gitFileBrowserResizeHandle.widthProvider = { [weak self] in
            self?.gitFileBrowserLastVisibleWidth ?? 0
        }
        gitFileBrowserResizeHandle.identifier = NSUserInterfaceItemIdentifier("gitFileBrowserResizeHandle")
        gitFileBrowserResizeHandle.resizeHandler = { [weak self] width in
            self?.resizeGitFileBrowser(to: width)
        }

        let contentRow = NSStackView(views: [gitFileBrowserColumn,
                                             gitFileBrowserResizeHandle,
                                             editorStack])
        contentRow.orientation = .horizontal
        contentRow.spacing = 0
        contentRow.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentRow.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let root = NSStackView(views: [bar, contentRow])
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
        let browserWidth = gitFileBrowserColumn.widthAnchor.constraint(equalToConstant: gitFileBrowserDefaultWidth)
        gitFileBrowserWidthConstraint = browserWidth
        browserWidth.isActive = true
        gitFileBrowserResizeHandle.widthAnchor.constraint(equalToConstant: gitFileBrowserResizeHandleWidth).isActive = true
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
        let start = DispatchTime.now().uptimeNanoseconds
        super.viewDidLayout()
        refreshPaneViewportWidths()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        if elapsed >= 8 {
            logInputPerformance("viewDidLayout",
                                milliseconds: elapsed,
                                metadata: "viewBounds=\(format(view.bounds.width))x\(format(view.bounds.height))")
        }
    }

    func load(left: URL, right: URL) {
        AppLogger.info("Received files to load left=\(left.path) right=\(right.path)")
        resetGitSession()
        saveTarget = .savePanel
        leftURL = left
        rightURL = right
        compare()
    }

    @objc func chooseLeft() {
        leftURL = pickFile()
        AppLogger.info("Left file selected: \(leftURL?.path ?? "none")")
        updateButtons()
    }

    @objc func chooseRight() {
        rightURL = pickFile()
        AppLogger.info("Right file selected: \(rightURL?.path ?? "none")")
        updateButtons()
    }

    @objc func compare() {
        guard let leftURL, let rightURL else { return }
        resetGitSession()
        saveTarget = .savePanel
        useCompareSyntaxFileNames(left: leftURL, right: rightURL)
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

    @objc func save() {
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
                    if let nextIndex = nextUnresolvedGitConflictIndex(after: selectedGitConflictIndex) {
                        phases.append(timed("updateGitControls") { updateGitControls() }.1)
                        phases.append(timed("loadNextConflict") { loadGitConflictFile(at: nextIndex) }.1)
                    } else {
                        phases.append(timed("returnToFileSelection") { returnToGitFileSelectionStart() }.1)
                    }
                    logPerformance("saveGit",
                                   phases: phases,
                                   metadata: "path=\(relativePath) bytes=\(text.utf8.count)",
                                   minimumTotalMilliseconds: 0)
                case .gitDiffPreview:
                    break
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
}
