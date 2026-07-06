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

    func mergedTextSelectionDetailLog(_ textView: NSTextView? = nil) -> String {
        guard let textView = textView ?? mergedTextView else { return "nil" }
        let range = textView.selectedRange()
        let text = textView.string as NSString
        return "\(range.location):\(range.length):\(textPositionLog(location: range.location, in: text))"
    }

    func textPositionLog(location: Int, in text: NSString) -> String {
        let safeLocation = min(max(location, 0), text.length)
        var line = 1
        var lineStart = 0
        var searchLocation = 0

        while searchLocation < safeLocation {
            let searchRange = NSRange(location: searchLocation, length: safeLocation - searchLocation)
            let newline = text.range(of: "\n", options: [], range: searchRange)
            guard newline.location != NSNotFound else { break }
            line += 1
            lineStart = NSMaxRange(newline)
            searchLocation = lineStart
        }

        let tailRange = NSRange(location: safeLocation, length: text.length - safeLocation)
        let nextNewline = text.range(of: "\n", options: [], range: tailRange)
        let lineEnd = nextNewline.location == NSNotFound ? text.length : nextNewline.location
        let clamped = safeLocation == location ? "" : ":clamped=\(safeLocation)"
        return "line=\(line):column=\(safeLocation - lineStart):lineRange=\(lineStart):\(max(lineEnd - lineStart, 0)):textLength=\(text.length)\(clamped)"
    }

    func mergedTextRangeAtSelectionLog(_ textView: NSTextView? = nil) -> String {
        guard let textView = textView ?? mergedTextView,
              let index = mergedTextRangeIndex(at: textView.selectedRange().location) else {
            return "nil"
        }
        return mergedTextRangeLog(mergedTextRanges[index])
    }

    func mergedTextRangeLog(_ range: MergedBlockTextRange?) -> String {
        guard let range else { return "nil" }
        return mergedTextRangeLog(range)
    }

    func mergedTextRangeLog(_ range: MergedBlockTextRange) -> String {
        let source = range.sourceLineRange.map { "\($0.location):\($0.length)" } ?? "nil"
        return "block=\(range.blockIndex):chars=\(range.characterRange.location):\(range.characterRange.length):editable=\(range.isEditable):source=\(source)"
    }

    func mergedTextRangesLog(_ ranges: [MergedBlockTextRange], limit: Int = 4) -> String {
        guard !ranges.isEmpty else { return "none" }
        let rangeText = ranges
            .prefix(limit)
            .map(mergedTextRangeLog)
            .joined(separator: "|")
        let suffix = ranges.count > limit ? "|more=\(ranges.count - limit)" : ""
        return "\(rangeText)\(suffix)"
    }

    func pendingSelectionLog(_ selection: PendingMergedSelection?) -> String {
        guard let selection else { return "nil" }
        let source = selection.sourceLineRange.map { "\($0.location):\($0.length)" } ?? "nil"
        let sourcePosition: String
        if let lineLocation = selection.sourceLineLocation,
           let column = selection.sourceColumn {
            sourcePosition = "\(lineLocation):\(column)"
        } else {
            sourcePosition = "nil"
        }
        return "\(selection.blockIndex):source=\(source):sourcePosition=\(sourcePosition):relative=\(selection.relativeLocation):\(selection.length)"
    }

    func blockList(_ indexes: [Int]) -> String {
        guard !indexes.isEmpty else { return "none" }
        return indexes.map(String.init).joined(separator: ",")
    }
}
