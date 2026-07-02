import AppKit

extension MainWindowController {
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


    @objc func selectGitConflictFile(_ sender: NSPopUpButton) {
        loadGitConflictFile(at: sender.indexOfSelectedItem)
    }

    func loadGitConflictFile(at index: Int) {
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
        gitFilePopup.removeAllItems()
        for file in gitConflictFiles {
            gitFilePopup.addItem(withTitle: gitFileTitle(for: file))
        }
        if let selectedGitConflictIndex, selectedGitConflictIndex >= 0, selectedGitConflictIndex < gitConflictFiles.count {
            gitFilePopup.selectItem(at: selectedGitConflictIndex)
        }
    }

    func gitFileTitle(for file: MDGitConflictFile) -> String {
        let relativePath = file.relativePath ?? ""
        if gitResolvedPaths.contains(relativePath) {
            return "[saved] \(relativePath)"
        }
        if !file.isTextConflict {
            return "[unsupported] \(relativePath)"
        }
        return relativePath
    }

    func nextUnresolvedGitConflictIndex(after currentIndex: Int?) -> Int? {
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

}
