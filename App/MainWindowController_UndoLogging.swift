import AppKit

extension MainWindowController {
    func logToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmed.isEmpty ? "none" : trimmed
        return token.replacingOccurrences(of: " ", with: "_")
    }

    func mergedTextSelectionLog() -> String {
        guard let textView = mergedTextView else { return "nil" }
        let range = textView.selectedRange()
        return "\(range.location):\(range.length)"
    }

    func pendingSelectionLog(_ selection: PendingMergedSelection?) -> String {
        guard let selection else { return "nil" }
        let source = selection.sourceLineRange.map { "\($0.location):\($0.length)" } ?? "nil"
        return "\(selection.blockIndex):source=\(source):relative=\(selection.relativeLocation):\(selection.length)"
    }

    func blockList(_ indexes: [Int]) -> String {
        guard !indexes.isEmpty else { return "none" }
        return indexes.map(String.init).joined(separator: ",")
    }
}
