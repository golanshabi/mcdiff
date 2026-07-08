import Foundation

extension MainWindowController {
    func clearPaneSyntaxFileNames() {
        paneSyntaxFileNames = [:]
    }

    func useSingleSyntaxFileName(_ fileName: String) {
        paneSyntaxFileNames = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, fileName) })
    }

    func useCompareSyntaxFileNames(left: URL, right: URL) {
        paneSyntaxFileNames = [
            .left: left.lastPathComponent,
            .merged: right.lastPathComponent,
            .right: right.lastPathComponent
        ]
    }

    func syntaxFileName(for pane: DiffPane) -> String? {
        paneSyntaxFileNames[pane]
    }

    func scheduleMergedSyntaxRefresh(after delay: TimeInterval = 1.0) {
        pendingMergedSyntaxRefresh?.cancel()
        guard mergedTextView != nil else { return }
        guard delay > 0 else {
            pendingMergedSyntaxRefresh = nil
            refreshMergedSyntaxHighlightingNow()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingMergedSyntaxRefresh = nil
            self?.refreshMergedSyntaxHighlightingNow()
        }
        pendingMergedSyntaxRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingMergedSyntaxRefresh() {
        pendingMergedSyntaxRefresh?.cancel()
        pendingMergedSyntaxRefresh = nil
    }

    func refreshMergedSyntaxHighlightingNow() {
        guard let clip = paneTextClipViews[.merged]?.first else { return }
        clip.refreshSyntaxHighlighting(preserveSelection: true)
    }
}
