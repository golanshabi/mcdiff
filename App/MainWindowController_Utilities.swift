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

    func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
