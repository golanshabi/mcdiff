import AppKit

extension MainWindowController {
    func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func updateButtons() {
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
        gitFilePopup.isHidden = true
        applyGitFileBrowserVisibility(isGitRepositoryMode: isGitRepositoryMode)
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
            case .gitDiffPreview:
                saveButton.title = "Diff Only"
                saveButton.isEnabled = false
            case .mergeToolOutput:
                saveButton.title = "Save Merge"
                saveButton.isEnabled = canSaveDocument
        }
    }

    func show(_ message: String) {
        AppLogger.error("Showing alert: \(message)")
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func markerlessConflictAlert(relativePath: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = markerlessConflictMessage
        alert.informativeText = "\(relativePath) is still marked unmerged by Git, but the file has no conflict markers. Add it to Git to mark it resolved and move it to Review Changes."
        alert.addButton(withTitle: "Add to Git")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    func shouldStageMarkerlessConflict(relativePath: String) -> Bool {
        AppLogger.error("Showing markerless conflict alert: \(relativePath)")
        return markerlessConflictAlert(relativePath: relativePath).runModal() == .alertFirstButtonReturn
    }

    func timed<T>(_ name: String, _ work: () throws -> T) rethrows -> (T, TimedPhase) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try work()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return (result, TimedPhase(name: name, milliseconds: Double(elapsed) / 1_000_000.0))
    }

    func logPerformance(_ operation: String,
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

    func logInputPerformance(_ operation: String,
                             milliseconds: Double,
                             metadata: String = "") {
        let rowCount = renderedBlockRows.values.reduce(0) { $0 + $1.rowCount }
        let documentBlockCount = document?.blocks.count ?? 0
        let gitMode = gitRepositoryRoot != nil
        let previewMode = isGitDiffPreview
        let metadataText = metadata.isEmpty ? "" : " \(metadata)"
        AppLogger.info("PERF input.\(operation) elapsed_ms=\(String(format: "%.1f", milliseconds)) blocks=\(documentBlockCount) rows=\(rowCount) gitMode=\(gitMode) previewMode=\(previewMode)\(metadataText)")
    }

    func logRenderTrace(_ operation: String,
                        milliseconds: Double,
                        metadata: String = "",
                        minimumMilliseconds: Double = 0) {
        guard milliseconds >= minimumMilliseconds else { return }

        let rowCount = renderedBlockRows.values.reduce(0) { $0 + $1.rowCount }
        let documentBlockCount = document?.blocks.count ?? 0
        let metadataText = metadata.isEmpty ? "" : " \(metadata)"
        AppLogger.info("PERF renderTrace.\(operation) elapsed_ms=\(String(format: "%.1f", milliseconds)) blocks=\(documentBlockCount) rows=\(rowCount) gitMode=\(gitRepositoryRoot != nil) previewMode=\(isGitDiffPreview)\(metadataText)")
    }

    func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
