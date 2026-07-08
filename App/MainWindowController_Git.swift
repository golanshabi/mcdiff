import AppKit

final class GitFileBrowserNode: NSObject {
    let title: String
    let fileIndex: Int?
    let isPlaceholder: Bool
    var children: [GitFileBrowserNode]

    init(title: String,
         fileIndex: Int? = nil,
         isPlaceholder: Bool = false,
         children: [GitFileBrowserNode] = []) {
        self.title = title
        self.fileIndex = fileIndex
        self.isPlaceholder = isPlaceholder
        self.children = children
    }

    var isCategory: Bool {
        fileIndex == nil && !isPlaceholder
    }
}

extension MainWindowController {
    func configureGitFileBrowser() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("gitFileBrowserColumn"))
        column.title = ""
        column.resizingMask = .autoresizingMask

        gitFileSearchField.identifier = NSUserInterfaceItemIdentifier("gitFileSearch")
        gitFileSearchField.placeholderString = "Search files"
        gitFileSearchField.sendsSearchStringImmediately = true
        gitFileSearchField.target = self
        gitFileSearchField.action = #selector(searchGitFiles(_:))

        gitFileOutline.identifier = NSUserInterfaceItemIdentifier("gitFileOutline")
        gitFileOutline.addTableColumn(column)
        gitFileOutline.outlineTableColumn = column
        gitFileOutline.headerView = nil
        gitFileOutline.rowSizeStyle = .small
        gitFileOutline.indentationPerLevel = 16
        gitFileOutline.allowsMultipleSelection = false
        gitFileOutline.allowsEmptySelection = false
        gitFileOutline.dataSource = self
        gitFileOutline.delegate = self

        gitFileBrowserScroll.identifier = NSUserInterfaceItemIdentifier("gitFileBrowserScroll")
        gitFileBrowserScroll.documentView = gitFileOutline
        gitFileBrowserScroll.hasVerticalScroller = true
        gitFileBrowserScroll.hasHorizontalScroller = true
        gitFileBrowserScroll.borderType = .lineBorder
        gitFileBrowserScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        gitFileBrowserScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        gitFileBrowserPanel.identifier = NSUserInterfaceItemIdentifier("gitFileBrowser")
        gitFileBrowserPanel.orientation = .vertical
        gitFileBrowserPanel.spacing = 6
        gitFileBrowserPanel.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        gitFileBrowserPanel.addArrangedSubview(gitFileSearchField)
        gitFileBrowserPanel.addArrangedSubview(gitFileBrowserScroll)
        gitFileBrowserPanel.isHidden = true
    }

    @objc func searchGitFiles(_ sender: NSSearchField) {
        updateGitControls()
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

        let (discoveredFiles, listPhase) = timed("listChanges") {
            MDGitChangedFiles(rootPath, &error)
        }
        phases.append(listPhase)
        guard let files = discoveredFiles else {
            logPerformance("loadGit", phases: phases, metadata: "failed=list", minimumTotalMilliseconds: 0)
            show(error?.localizedDescription ?? "Could not read git changes.")
            updateButtons()
            return
        }
        logPerformance("loadGit", phases: phases, metadata: "files=\(files.count)", minimumTotalMilliseconds: 0)

        gitRepositoryRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
        gitConflictFiles = files
        if gitConflictFiles.isEmpty {
            document = nil
            gitStatusLabel.stringValue = "No git changes found."
            render(preservingVerticalPosition: false)
            updateButtons()
            return
        }

        updateGitControls()
        gitStatusLabel.stringValue = gitFileSelectionSummary()
        updateButtons()
        view.window?.makeFirstResponder(gitFileOutline)
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


    @objc func selectGitConflictFile(_ sender: NSPopUpButton) {
        guard let index = sender.selectedItem?.representedObject as? Int else {
            updateGitControls()
            return
        }
        loadGitConflictFile(at: index)
    }

    func loadGitConflictFile(at index: Int) {
        guard index >= 0, index < gitConflictFiles.count, let gitRepositoryRoot else { return }

        selectedGitConflictIndex = index
        let file = gitConflictFiles[index]
        let relativePath = file.relativePath ?? ""
        let message = file.message ?? ""
        var phases = [TimedPhase]()
        phases.append(timed("updateGitControls") { updateGitControls() }.1)

        let isResolvedConflict = file.isConflict && gitResolvedPaths.contains(relativePath)
        guard file.isConflict && !isResolvedConflict else {
            saveTarget = .gitDiffPreview
            let status = isResolvedConflict ? "saved" : (file.statusDescription ?? "changed")
            gitStatusLabel.stringValue = "Diffing \(relativePath) (\(status), HEAD -> worktree)"
            do {
                phases.append(contentsOf: try loadGitDiffDocument(file: file, repositoryRoot: gitRepositoryRoot))
                phases.append(timed("render") { resetEditorStateAfterDocumentLoad() }.1)
                logPerformance("loadGitDiffFile",
                               phases: phases,
                               metadata: "path=\(relativePath) status=\(status)",
                               minimumTotalMilliseconds: 0)
            } catch {
                AppLogger.error("Git diff load failed: \(error.localizedDescription)")
                document = nil
                gitStatusLabel.stringValue = "Could not diff \(relativePath)"
                render(preservingVerticalPosition: false)
                show(error.localizedDescription)
            }
            updateButtons()
            return
        }

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

    func loadGitDiffDocument(file: MDGitConflictFile, repositoryRoot: URL) throws -> [TimedPhase] {
        var phases = [TimedPhase]()
        let relativePath = file.relativePath ?? ""
        let headRelativePath = file.headRelativePath ?? relativePath

        var headError: NSError?
        let (headText, headPhase) = timed("readHead") {
            MDGitHeadFileText(repositoryRoot.path, headRelativePath, &headError)
        }
        phases.append(headPhase)
        guard let leftText = headText else {
            throw headError ?? NSError(domain: "mcdiff", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Could not read \(headRelativePath) from HEAD."
            ])
        }

        let worktreeURL = repositoryRoot.appendingPathComponent(relativePath)
        let (rightText, readPhase) = try timed("readWorktree") {
            try gitWorktreeText(from: worktreeURL)
        }
        phases.append(readPhase)

        var diffError: NSError?
        let (parsedDocument, diffPhase) = timed("diff") {
            MDMakeDiff(leftText, rightText, &diffError)
        }
        phases.append(diffPhase)
        guard let parsed = parsedDocument else {
            throw diffError ?? NSError(domain: "mcdiff", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not build git diff for \(relativePath)."
            ])
        }
        document = parsed
        return phases
    }

    func gitWorktreeText(from url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw NSError(domain: "mcdiff", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Could not read \(url.path) as UTF-8 text. Binary files are not supported yet."
            ])
        }
    }

    func loadConflictDocument(from url: URL) throws -> [TimedPhase] {
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

    func resetGitSession() {
        gitRepositoryRoot = nil
        gitConflictFiles = []
        gitFileBrowserNodes = []
        gitFileSearchField.stringValue = ""
        isReloadingGitFileBrowser = true
        gitFileOutline.reloadData()
        isReloadingGitFileBrowser = false
        selectedGitConflictIndex = nil
        gitResolvedPaths = []
        gitFilePopup.removeAllItems()
        gitStatusLabel.stringValue = ""
    }

    func resetEditorStateAfterDocumentLoad() {
        pendingMergedEdit = nil
        pendingMergedSelection = nil
        compactContextExpansions = [:]
        mergeUndoManager.removeAllActions(withTarget: self)
        resetHorizontalOffsets()
        render(preservingVerticalPosition: false)
    }

    func updateGitControls() {
        let searchText = gitFileSearchText()
        let conflictedIndexes = gitConflictFiles.indices.filter { index in
            let file = gitConflictFiles[index]
            return file.isConflict
                && !gitResolvedPaths.contains(file.relativePath ?? "")
                && gitFileMatchesSearch(file, searchText: searchText)
        }
        let changedIndexes = gitConflictFiles.indices.filter { index in
            let file = gitConflictFiles[index]
            return (!file.isConflict || gitResolvedPaths.contains(file.relativePath ?? ""))
                && gitFileMatchesSearch(file, searchText: searchText)
        }
        let emptyTitle = searchText.isEmpty ? "No files" : "No matches"
        gitFileBrowserNodes = [
            gitFileBrowserSection(title: "Needs Resolution",
                                  indexes: Array(conflictedIndexes),
                                  emptyTitle: emptyTitle),
            gitFileBrowserSection(title: "Review Changes",
                                  indexes: Array(changedIndexes),
                                  emptyTitle: emptyTitle)
        ]
        reloadGitFileBrowser()
    }

    func gitFileBrowserSection(title: String, indexes: [Int], emptyTitle: String) -> GitFileBrowserNode {
        let children = indexes.isEmpty
            ? [GitFileBrowserNode(title: emptyTitle, isPlaceholder: true)]
            : indexes.map { index in
                GitFileBrowserNode(title: gitFileTitle(for: gitConflictFiles[index]),
                                   fileIndex: index)
            }
        return GitFileBrowserNode(title: title, children: children)
    }

    func reloadGitFileBrowser() {
        isReloadingGitFileBrowser = true
        gitFileOutline.reloadData()
        if !gitFileSearchText().isEmpty {
            for node in gitFileBrowserNodes {
                gitFileOutline.expandItem(node)
            }
        }

        if let selectedGitConflictIndex,
           let node = gitFileBrowserNode(for: selectedGitConflictIndex),
           let parent = gitFileBrowserParentNode(containing: selectedGitConflictIndex) {
            gitFileOutline.expandItem(parent)
            let row = gitFileOutline.row(forItem: node)
            if row >= 0 {
                gitFileOutline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                gitFileOutline.scrollRowToVisible(row)
            }
        } else if gitFileOutline.numberOfRows > 0 {
            gitFileOutline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        isReloadingGitFileBrowser = false
    }

    func gitFileSearchText() -> String {
        gitFileSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func gitFileMatchesSearch(_ file: MDGitConflictFile, searchText: String) -> Bool {
        let tokens = normalizedGitFileSearchText(searchText)
            .split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }

        let haystack = normalizedGitFileSearchText([
            gitFileTitle(for: file),
            file.relativePath ?? "",
            file.statusDescription ?? "",
            file.message ?? ""
        ].joined(separator: " "))
        return tokens.allSatisfy { haystack.contains($0) }
    }

    func normalizedGitFileSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    func gitFileBrowserNode(for fileIndex: Int) -> GitFileBrowserNode? {
        for section in gitFileBrowserNodes {
            if let node = section.children.first(where: { $0.fileIndex == fileIndex }) {
                return node
            }
        }
        return nil
    }

    func gitFileBrowserParentNode(containing fileIndex: Int) -> GitFileBrowserNode? {
        gitFileBrowserNodes.first { section in
            section.children.contains { $0.fileIndex == fileIndex }
        }
    }

    func gitFileTitle(for file: MDGitConflictFile) -> String {
        let relativePath = file.relativePath ?? ""
        if gitResolvedPaths.contains(relativePath) {
            return "\(relativePath) (saved)"
        }
        if file.isConflict && !file.isTextConflict {
            return "\(relativePath) (unsupported)"
        }
        if file.isConflict {
            return relativePath
        }
        if let status = file.statusDescription, !status.isEmpty {
            return "\(relativePath) (\(status))"
        }
        return relativePath
    }

    func gitFileSelectionSummary() -> String {
        let conflictedCount = gitConflictFiles.filter { file in
            file.isConflict && !gitResolvedPaths.contains(file.relativePath ?? "")
        }.count
        let changedCount = gitConflictFiles.count - conflictedCount
        let resolutionText = conflictedCount == 1
            ? "1 file needs resolution"
            : "\(conflictedCount) files need resolution"
        let reviewText = changedCount == 1
            ? "1 change to review"
            : "\(changedCount) changes to review"
        return "Choose a file (\(resolutionText), \(reviewText))."
    }

    func nextUnresolvedGitConflictIndex(after currentIndex: Int?) -> Int? {
        guard !gitConflictFiles.isEmpty else { return nil }
        let start = ((currentIndex ?? -1) + 1) % gitConflictFiles.count
        for offset in 0..<gitConflictFiles.count {
            let index = (start + offset) % gitConflictFiles.count
            let file = gitConflictFiles[index]
            if file.isConflict && file.isTextConflict && !gitResolvedPaths.contains(file.relativePath ?? "") {
                return index
            }
        }
        return nil
    }

}

extension MainWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return gitFileBrowserNodes.count
        }
        return (item as? GitFileBrowserNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return gitFileBrowserNodes[index]
        }
        return (item as? GitFileBrowserNode)?.children[index] ?? GitFileBrowserNode(title: "")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? GitFileBrowserNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? GitFileBrowserNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("gitFileBrowserCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier

        let textField: NSTextField
        if let existing = cell.textField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        textField.stringValue = node.title
        textField.font = node.isCategory
            ? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.textColor = node.isPlaceholder ? .secondaryLabelColor : .labelColor
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? GitFileBrowserNode else { return true }
        return !node.isPlaceholder
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingGitFileBrowser,
              let outlineView = notification.object as? NSOutlineView,
              outlineView === gitFileOutline else {
            return
        }

        let row = gitFileOutline.selectedRow
        guard row >= 0,
              let node = gitFileOutline.item(atRow: row) as? GitFileBrowserNode,
              let fileIndex = node.fileIndex,
              fileIndex != selectedGitConflictIndex else {
            return
        }
        loadGitConflictFile(at: fileIndex)
    }
}
