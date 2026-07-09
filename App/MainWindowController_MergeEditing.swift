import AppKit

extension MainWindowController {
    struct BoundaryReclaim {
        let blockIndex: Int
        let nextBlockIndex: Int
        let reclaimedLines: [String]
        let suffixStartOffset: Int
    }

    struct BoundaryDeletion {
        let blockIndex: Int
        let nextBlockIndex: Int
        let previousLines: [String]
        let nextLines: [String]
    }

    @objc func undo(_ sender: Any?) {
        performUndo()
    }

    @objc func redo(_ sender: Any?) {
        performRedo()
    }

    func performUndo() {
        guard mergeUndoManager.canUndo else {
            AppLogger.info("Undo requested but no undo action is available.")
            NSSound.beep()
            return
        }

        let undoStart = DispatchTime.now().uptimeNanoseconds
        let actionName = logToken(mergeUndoManager.undoActionName)
        let scrollYBefore = scroll.contentView.bounds.origin.y
        let selectionBefore = mergedTextSelectionLog()
        let canRedoBefore = mergeUndoManager.canRedo
        let rangeCountBefore = mergedTextRanges.count
        mergeUndoManager.undo()
        let elapsed = DispatchTime.now().uptimeNanoseconds - undoStart
        logPerformance("undo",
                       phases: [TimedPhase(name: "total", milliseconds: Double(elapsed) / 1_000_000.0)],
                       metadata: "action=\(actionName) canUndoBefore=true canRedoBefore=\(canRedoBefore) canUndoAfter=\(mergeUndoManager.canUndo) canRedoAfter=\(mergeUndoManager.canRedo) scrollY=\(format(scrollYBefore))->\(format(scroll.contentView.bounds.origin.y)) selection=\(selectionBefore)->\(mergedTextSelectionLog()) ranges=\(rangeCountBefore)->\(mergedTextRanges.count) blocks=\(document?.blocks.count ?? 0)",
                       minimumTotalMilliseconds: 0)
    }

    func performRedo() {
        guard mergeUndoManager.canRedo else {
            AppLogger.info("Redo requested but no redo action is available.")
            NSSound.beep()
            return
        }

        let redoStart = DispatchTime.now().uptimeNanoseconds
        let actionName = logToken(mergeUndoManager.redoActionName)
        let scrollYBefore = scroll.contentView.bounds.origin.y
        let selectionBefore = mergedTextSelectionLog()
        let canUndoBefore = mergeUndoManager.canUndo
        let rangeCountBefore = mergedTextRanges.count
        mergeUndoManager.redo()
        let elapsed = DispatchTime.now().uptimeNanoseconds - redoStart
        logPerformance("redo",
                       phases: [TimedPhase(name: "total", milliseconds: Double(elapsed) / 1_000_000.0)],
                       metadata: "action=\(actionName) canUndoBefore=\(canUndoBefore) canRedoBefore=true canUndoAfter=\(mergeUndoManager.canUndo) canRedoAfter=\(mergeUndoManager.canRedo) scrollY=\(format(scrollYBefore))->\(format(scroll.contentView.bounds.origin.y)) selection=\(selectionBefore)->\(mergedTextSelectionLog()) ranges=\(rangeCountBefore)->\(mergedTextRanges.count) blocks=\(document?.blocks.count ?? 0)",
                       minimumTotalMilliseconds: 0)
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
        let replacement = replacementString ?? ""
        pendingMergedEdit = PendingMergedEdit(ranges: ranges,
                                              blockIndexes: ranges.map(\.blockIndex),
                                              oldUnionRange: NSRange(location: unionStart,
                                                                     length: max(unionEnd - unionStart, 0)),
                                              affectedRange: affectedCharRange,
                                              replacement: replacement,
                                              undoSelection: pendingSelection(from: affectedCharRange,
                                                                              in: firstRange,
                                                                              text: textView.string as NSString))
        if replacement.contains("\n") {
            AppLogger.info("MERGE_EDIT_CAPTURE replacementKind=\(replacementKind(replacement)) affectedRange=\(affectedCharRange.location):\(affectedCharRange.length) oldUnionRange=\(unionStart):\(max(unionEnd - unionStart, 0)) selection=\(mergedTextSelectionDetailLog(textView)) activeRange=\(mergedTextRangeAtSelectionLog(textView)) ranges=\(mergedTextRangesLog(ranges))")
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === mergedTextView else { return }
        defer { revealMergedSelectionHorizontally() }
        scheduleMergedSyntaxRefresh()
        guard let edit = pendingMergedEdit else { return }
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
        let boundaryDeletion = followingBlockBoundaryDeletion(edit: edit,
                                                              editedLines: editedLines)
        let boundaryReclaim = followingBlockBoundaryReclaim(edit: edit,
                                                            editedLines: editedLines)
        var snapshotBlockIndexes = edit.blockIndexes
        if let boundaryReclaim {
            snapshotBlockIndexes.append(boundaryReclaim.nextBlockIndex)
        }
        let beforeSnapshots = snapshots(for: snapshotBlockIndexes)
        let beforeRowCounts = Dictionary(uniqueKeysWithValues: edit.blockIndexes.compactMap { blockIndex -> (Int, Int)? in
            guard let rows = renderedBlockRows[blockIndex] else { return nil }
            return (blockIndex, rows.rowCount)
        })
        if let boundaryDeletion {
            applyFollowingBlockBoundaryDeletion(boundaryDeletion)
        } else {
            for (offset, range) in edit.ranges.enumerated() where range.blockIndex < document.blocks.count {
                normalize(block: document.blocks[range.blockIndex],
                          editedLines: offset == 0 ? editedLines : [],
                          editedRange: offset == 0 ? range : nil)
            }
        }
        if let boundaryReclaim {
            applyFollowingBlockBoundaryReclaim(boundaryReclaim, editedLines: editedLines)
        }
        registerMergedUndo(before: beforeSnapshots, actionName: "Edit", restoreSelection: edit.undoSelection)
        let firstEditedRange = edit.ranges[0]
        pendingMergedSelection = pendingSelection(from: textView.selectedRange(),
                                                  blockIndex: firstEditedRange.blockIndex,
                                                  sourceLineRange: firstEditedRange.sourceLineRange,
                                                  blockRange: newBlockRange,
                                                  text: text)
        if let boundaryReclaim {
            movePendingSelectionIntoReclaimedBlockIfNeeded(boundaryReclaim)
        }
        var renderDecision: MergedEditRenderDecision
        if boundaryDeletion != nil {
            renderDecision = MergedEditRenderDecision(shouldRender: true,
                                                      reason: "boundary_deletion",
                                                      detail: "")
        } else if boundaryReclaim != nil {
            renderDecision = MergedEditRenderDecision(shouldRender: true,
                                                      reason: "boundary_reclaim",
                                                      detail: "")
        } else {
            renderDecision = mergedEditRenderDecision(edit: edit,
                                                      beforeRowCounts: beforeRowCounts,
                                                      editedLines: editedLines)
        }
        let traceSelection = edit.replacement.contains("\n") ||
            shouldRefreshRenderPlanInline(for: renderDecision)
        if traceSelection {
            AppLogger.info("MERGE_EDIT_SELECTION stage=before_apply replacementKind=\(replacementKind(edit.replacement)) renderReason=\(renderDecision.reason) renderDetail=\(logToken(renderDecision.detail)) pending=\(pendingSelectionLog(pendingMergedSelection)) selection=\(mergedTextSelectionDetailLog(textView)) activeRange=\(mergedTextRangeAtSelectionLog(textView)) firstEditedRange=\(mergedTextRangeLog(firstEditedRange)) affectedRange=\(edit.affectedRange.location):\(edit.affectedRange.length) oldUnionRange=\(edit.oldUnionRange.location):\(edit.oldUnionRange.length) newBlockRange=\(newBlockRange.location):\(newBlockRange.length) editedLines=\(editedLines.count) boundaryDeletion=\(boundaryDeletion != nil) boundaryReclaim=\(boundaryReclaim != nil)")
        }
        var applyRoute = "inline_ranges"
        if renderDecision.shouldRender {
            applyRoute = "render"
            render(preservingVerticalPosition: true)
        } else if shouldRefreshRenderPlanInline(for: renderDecision) {
            applyRoute = "inline_render_plan"
            let updateContentWidths = shouldUpdateContentWidthsInline(for: renderDecision)
            if !refreshRenderedPanesAfterInlineMergedEdit(updateContentWidths: updateContentWidths) {
                applyRoute = "inline_render_plan_fallback_render"
                renderDecision = MergedEditRenderDecision(shouldRender: true,
                                                          reason: "\(renderDecision.reason)_fallback",
                                                          detail: "")
                render(preservingVerticalPosition: true)
            }
        } else {
            updateMergedTextRangesAfterInlineEdit(range: firstEditedRange, newBlockRange: newBlockRange)
            updatePaneBackgroundRuns(for: firstBlockIndex)
        }
        updateButtons()
        if traceSelection {
            AppLogger.info("MERGE_EDIT_SELECTION stage=after_apply route=\(applyRoute) renderReason=\(renderDecision.reason) pending=\(pendingSelectionLog(pendingMergedSelection)) selection=\(mergedTextSelectionDetailLog(textView)) activeRange=\(mergedTextRangeAtSelectionLog(textView)) firstResponder=\(view.window?.firstResponder === textView)")
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - editStart
        logPerformance("edit",
                       phases: [TimedPhase(name: "total", milliseconds: Double(elapsed) / 1_000_000.0)],
                       metadata: mergedEditLogMetadata(edit: edit,
                                                       replacementLength: replacementLength,
                                                       newBlockRange: newBlockRange,
                                                       editedLines: editedLines,
                                                       beforeRowCounts: beforeRowCounts,
                                                       renderDecision: renderDecision,
                                                       documentBlockCount: document.blocks.count,
                                                       selectedRange: textView.selectedRange()),
                       minimumTotalMilliseconds: 50)
    }

    struct MergedEditRenderDecision {
        let shouldRender: Bool
        let reason: String
        let detail: String
    }

    func mergedEditRenderDecision(edit: PendingMergedEdit,
                                  beforeRowCounts: [Int: Int],
                                  editedLines: [String]) -> MergedEditRenderDecision {
        guard edit.blockIndexes.count == 1 else {
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "multi_block",
                                            detail: "affectedBlocks=\(edit.blockIndexes.count)")
        }
        guard let blockIndex = edit.blockIndexes.first else {
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "missing_block",
                                            detail: "")
        }
        guard let document else {
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "missing_document",
                                            detail: "")
        }
        guard blockIndex >= 0,
              blockIndex < document.blocks.count else {
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "invalid_block",
                                            detail: "block=\(blockIndex) blocks=\(document.blocks.count)")
        }

        let block = document.blocks[blockIndex]
        guard let beforeRowCount = beforeRowCounts[blockIndex] else {
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "missing_before_rows",
                                            detail: "block=\(blockIndex)")
        }

        let afterRowCount = renderedRowCount(for: block, blockIndex: blockIndex)
        if beforeRowCount != afterRowCount {
            if canInlineRenderPlanEdit(edit: edit,
                                       block: block,
                                       editedLines: editedLines) {
                return MergedEditRenderDecision(shouldRender: false,
                                                reason: "inline_row_count",
                                                detail: "beforeRows=\(beforeRowCount) afterRows=\(afterRowCount)")
            }
            if canInlineRenderPlanStructureEdit(edit: edit,
                                                block: block,
                                                editedLines: editedLines) {
                return MergedEditRenderDecision(shouldRender: false,
                                                reason: "inline_row_count_width",
                                                detail: "beforeRows=\(beforeRowCount) afterRows=\(afterRowCount)")
            }
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "row_count",
                                            detail: "beforeRows=\(beforeRowCount) afterRows=\(afterRowCount)")
        }

        if let sourceLineRange = edit.ranges.first?.sourceLineRange,
           sourceLineRange.length != editedLines.count {
            if canInlineRenderPlanEdit(edit: edit,
                                       block: block,
                                       editedLines: editedLines) {
                return MergedEditRenderDecision(shouldRender: false,
                                                reason: "inline_source_line_count",
                                                detail: "sourceLines=\(sourceLineRange.length) editedLines=\(editedLines.count)")
            }
            if canInlineRenderPlanStructureEdit(edit: edit,
                                                block: block,
                                                editedLines: editedLines) {
                return MergedEditRenderDecision(shouldRender: false,
                                                reason: "inline_source_line_count_width",
                                                detail: "sourceLines=\(sourceLineRange.length) editedLines=\(editedLines.count)")
            }
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "source_line_count",
                                            detail: "sourceLines=\(sourceLineRange.length) editedLines=\(editedLines.count)")
        }

        let maxEditedWidth = editedLines.map(measuredLineWidth).max() ?? 0
        let maxSharedWidth = sharedMaxContentWidth()
        if maxEditedWidth > maxSharedWidth + 1 {
            if canInlineRenderPlanStructureEdit(edit: edit,
                                                block: block,
                                                editedLines: editedLines) {
                return MergedEditRenderDecision(shouldRender: false,
                                                reason: "inline_width",
                                                detail: "editedWidth=\(format(maxEditedWidth)) sharedWidth=\(format(maxSharedWidth))")
            }
            return MergedEditRenderDecision(shouldRender: true,
                                            reason: "width",
                                            detail: "editedWidth=\(format(maxEditedWidth)) sharedWidth=\(format(maxSharedWidth))")
        }

        return MergedEditRenderDecision(shouldRender: false,
                                        reason: "inline",
                                        detail: "beforeRows=\(beforeRowCount) afterRows=\(afterRowCount)")
    }

    func mergedEditLogMetadata(edit: PendingMergedEdit,
                               replacementLength: Int,
                               newBlockRange: NSRange,
                               editedLines: [String],
                               beforeRowCounts: [Int: Int],
                               renderDecision: MergedEditRenderDecision,
                               documentBlockCount: Int,
                               selectedRange: NSRange) -> String {
        let blockText = edit.blockIndexes.map(String.init).joined(separator: ",")
        let rangeText = edit.ranges
            .map { range in
                let source = range.sourceLineRange.map { "\($0.location):\($0.length)" } ?? "nil"
                return "\(range.blockIndex)@\(range.characterRange.location):\(range.characterRange.length):editable=\(range.isEditable):source=\(source)"
            }
            .joined(separator: "|")
        let beforeRowsText = beforeRowCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let editedLineLengths = editedLines
            .prefix(5)
            .map { "\(($0 as NSString).length)" }
            .joined(separator: ",")
        let detailText = renderDecision.detail.isEmpty ? "" : " renderDetail=\(renderDecision.detail)"
        return "affectedBlocks=\(edit.blockIndexes.count) blockIndexes=\(blockText) ranges=\(rangeText) replacementKind=\(replacementKind(edit.replacement)) replacementLength=\(replacementLength) affectedRange=\(edit.affectedRange.location):\(edit.affectedRange.length) oldUnionRange=\(edit.oldUnionRange.location):\(edit.oldUnionRange.length) newBlockRange=\(newBlockRange.location):\(newBlockRange.length) editedLines=\(editedLines.count) editedLineLengths=\(editedLineLengths) beforeRows=\(beforeRowsText) blocks=\(documentBlockCount) rendered=\(renderDecision.shouldRender) renderReason=\(renderDecision.reason)\(detailText) selection=\(selectedRange.location):\(selectedRange.length)"
    }

    func replacementKind(_ replacement: String) -> String {
        if replacement.isEmpty {
            return "delete"
        }
        if replacement == " " {
            return "space"
        }
        if replacement == "\n" {
            return "newline"
        }
        if replacement == "\t" {
            return "tab"
        }
        if replacement.allSatisfy({ $0 == " " }) {
            return "spaces"
        }
        if replacement.contains("\n") {
            return "multiline"
        }
        return "text"
    }

    func renderedRowCount(for block: MDBlock, blockIndex: Int) -> Int {
        let displayed = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map {
            ($0, displayedContent(for: block, blockIndex: blockIndex, pane: $0, mergedStartLine: 1))
        })
        return renderRowCount(for: block, displayed: displayed)
    }

    func updateMergedTextRangesAfterInlineEdit(range oldRange: MergedBlockTextRange, newBlockRange: NSRange) {
        guard let rangeIndex = mergedTextRanges.firstIndex(where: { mergedRange($0, matches: oldRange) })
                ?? mergedTextRanges.firstIndex(where: {
                    $0.blockIndex == oldRange.blockIndex &&
                    sameRange($0.sourceLineRange, oldRange.sourceLineRange)
                }) else {
            AppLogger.info("Skipped inline range update; missing range block=\(oldRange.blockIndex)")
            return
        }

        let oldRange = mergedTextRanges[rangeIndex]
        let delta = newBlockRange.length - oldRange.characterRange.length
        mergedTextRanges[rangeIndex] = MergedBlockTextRange(blockIndex: oldRange.blockIndex,
                                                            characterRange: newBlockRange,
                                                            isEditable: oldRange.isEditable,
                                                            sourceLineRange: oldRange.sourceLineRange)
        guard delta != 0, rangeIndex + 1 < mergedTextRanges.count else { return }

        for index in (rangeIndex + 1)..<mergedTextRanges.count {
            let range = mergedTextRanges[index]
            mergedTextRanges[index] = MergedBlockTextRange(blockIndex: range.blockIndex,
                                                           characterRange: NSRange(location: range.characterRange.location + delta,
                                                                                   length: range.characterRange.length),
                                                           isEditable: range.isEditable,
                                                           sourceLineRange: range.sourceLineRange)
        }
    }

    func updatePaneBackgroundRuns(for blockIndex: Int) {
        guard let document,
              blockIndex >= 0,
              blockIndex < document.blocks.count,
              let rows = renderedBlockRows[blockIndex] else {
            return
        }

        let block = document.blocks[blockIndex]
        for pane in DiffPane.allCases {
            guard let view = paneColumnViews[pane] else { continue }
            var runs = view.backgroundRuns.filter { $0.startRow != rows.startRow }
            if let color = backgroundColor(for: block, pane: pane) {
                let run = PaneBackgroundRun(startRow: rows.startRow,
                                            rowCount: rows.rowCount,
                                            color: color)
                let insertIndex = runs.firstIndex { $0.startRow > rows.startRow } ?? runs.endIndex
                runs.insert(run, at: insertIndex)
            }
            view.backgroundRuns = runs
        }
    }

    func snapshots(for blockIndexes: [Int]) -> [MergedBlockSnapshot] {
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

    func apply(snapshots: [MergedBlockSnapshot]) {
        guard let document else { return }
        for snapshot in snapshots where snapshot.blockIndex >= 0 && snapshot.blockIndex < document.blocks.count {
            let block = document.blocks[snapshot.blockIndex]
            block.pick = snapshot.pick
            block.manualLines = snapshot.manualLines
        }
    }

    func mergedTextRanges(affectedBy affectedRange: NSRange) -> [MergedBlockTextRange] {
        guard !mergedTextRanges.isEmpty else { return [] }
        let startIndex = mergedTextRangeIndex(at: affectedRange.location)
        let endLocation = affectedRange.length == 0 ? affectedRange.location : max(NSMaxRange(affectedRange) - 1, affectedRange.location)
        let endIndex = mergedTextRangeIndex(at: endLocation)
        guard let startIndex, let endIndex else { return [] }
        let lower = min(startIndex, endIndex)
        var upper = max(startIndex, endIndex)
        let affectedEnd = NSMaxRange(affectedRange)
        while affectedRange.length > 0,
              upper + 1 < mergedTextRanges.count,
              affectedEnd >= mergedTextRanges[upper + 1].characterRange.location {
            upper += 1
        }
        let ranges = Array(mergedTextRanges[lower...upper])
        guard ranges.allSatisfy(\.isEditable) else { return [] }
        return ranges
    }

    func mergedTextRangeIndex(at location: Int) -> Int? {
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

    func normalize(block: MDBlock, editedLines: [String]) {
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

    func normalize(block: MDBlock,
                           editedLines: [String],
                           editedRange: MergedBlockTextRange?) {
        guard block.kind == .equal,
              let sourceLineRange = editedRange?.sourceLineRange else {
            normalize(block: block, editedLines: editedLines)
            return
        }

        var fullLines = mergedLines(for: block, start: 1).lines
        guard sourceLineRange.location >= 0,
              NSMaxRange(sourceLineRange) <= fullLines.count else {
            normalize(block: block, editedLines: editedLines)
            return
        }

        let replacementRange = sourceLineRange.location..<NSMaxRange(sourceLineRange)
        fullLines.replaceSubrange(replacementRange, with: editedLines)
        normalize(block: block, editedLines: fullLines)
    }

    func followingBlockBoundaryDeletion(edit: PendingMergedEdit,
                                                editedLines: [String]) -> BoundaryDeletion? {
        guard edit.replacement.isEmpty,
              edit.affectedRange.length == 1,
              edit.ranges.count == 2,
              let firstRange = edit.ranges.first,
              let secondRange = edit.ranges.dropFirst().first,
              edit.affectedRange.location == NSMaxRange(firstRange.characterRange),
              NSMaxRange(edit.affectedRange) == secondRange.characterRange.location,
              secondRange.blockIndex == firstRange.blockIndex + 1,
              let document,
              firstRange.blockIndex >= 0,
              secondRange.blockIndex >= 0,
              firstRange.blockIndex < document.blocks.count,
              secondRange.blockIndex < document.blocks.count,
              editedLines.count >= 1 else {
            return nil
        }

        let firstBlock = document.blocks[firstRange.blockIndex]
        let secondBlock = document.blocks[secondRange.blockIndex]
        let firstOriginalLines = mergedLines(for: firstBlock, start: 1).lines
        let secondOriginalLines = mergedLines(for: secondBlock, start: 1).lines
        guard !firstOriginalLines.isEmpty,
              !secondOriginalLines.isEmpty,
              editedLines.count == firstOriginalLines.count + secondOriginalLines.count - 1 else {
            return nil
        }

        let previousLineCount = firstOriginalLines.count
        let previousLines = Array(editedLines.prefix(previousLineCount))
        let nextLines = Array(editedLines.dropFirst(previousLineCount))
        return BoundaryDeletion(blockIndex: firstRange.blockIndex,
                                nextBlockIndex: secondRange.blockIndex,
                                previousLines: previousLines,
                                nextLines: nextLines)
    }

    func applyFollowingBlockBoundaryDeletion(_ deletion: BoundaryDeletion) {
        guard let document,
              deletion.blockIndex >= 0,
              deletion.nextBlockIndex >= 0,
              deletion.blockIndex < document.blocks.count,
              deletion.nextBlockIndex < document.blocks.count else {
            return
        }

        normalize(block: document.blocks[deletion.blockIndex], editedLines: deletion.previousLines)
        normalize(block: document.blocks[deletion.nextBlockIndex], editedLines: deletion.nextLines)
    }

    func followingBlockBoundaryReclaim(edit: PendingMergedEdit,
                                               editedLines: [String]) -> BoundaryReclaim? {
        guard edit.replacement.contains("\n"),
              edit.blockIndexes.count == 1,
              let blockIndex = edit.blockIndexes.first,
              let document,
              blockIndex >= 0,
              blockIndex + 1 < document.blocks.count,
              !editedLines.isEmpty else {
            return nil
        }

        let nextBlockIndex = blockIndex + 1
        let nextBlock = document.blocks[nextBlockIndex]
        guard let reclaimedLines = reclaimableLines(for: nextBlock, fromSuffixOf: editedLines) else {
            return nil
        }

        let remainingLines = Array(editedLines.dropLast(reclaimedLines.count))
        guard remainingLines.count < editedLines.count else { return nil }

        return BoundaryReclaim(blockIndex: blockIndex,
                               nextBlockIndex: nextBlockIndex,
                               reclaimedLines: reclaimedLines,
                               suffixStartOffset: characterOffset(forRow: remainingLines.count, in: editedLines))
    }

    func applyFollowingBlockBoundaryReclaim(_ reclaim: BoundaryReclaim,
                                                    editedLines: [String]) {
        guard let document,
              reclaim.blockIndex >= 0,
              reclaim.nextBlockIndex >= 0,
              reclaim.blockIndex < document.blocks.count,
              reclaim.nextBlockIndex < document.blocks.count else {
            return
        }

        let remainingLines = Array(editedLines.dropLast(reclaim.reclaimedLines.count))
        normalize(block: document.blocks[reclaim.blockIndex], editedLines: remainingLines)
        let nextBlock = document.blocks[reclaim.nextBlockIndex]
        let nextLines = reclaim.reclaimedLines + mergedLines(for: nextBlock, start: 1).lines
        normalize(block: document.blocks[reclaim.nextBlockIndex],
                  editedLines: nextLines)
    }

    func reclaimableLines(for block: MDBlock, fromSuffixOf lines: [String]) -> [String]? {
        if block.kind == .equal,
           block.pick == .manual {
            let originalLines = block.leftLines ?? []
            let currentLines = block.manualLines ?? []
            let missingCount = originalLines.count - currentLines.count
            if missingCount > 0,
               Array(originalLines.suffix(currentLines.count)) == currentLines {
                let missingPrefix = Array(originalLines.prefix(missingCount))
                if Array(lines.suffix(missingPrefix.count)) == missingPrefix {
                    return missingPrefix
                }
            }
        }

        let candidates = [block.leftLines ?? [], block.rightLines ?? []]
        return candidates.first { candidate in
            guard block.pick == .manual,
                  (block.manualLines ?? []).isEmpty,
                  !candidate.isEmpty,
                  candidate.count <= lines.count else { return false }
            return Array(lines.suffix(candidate.count)) == candidate
        }
    }

    func movePendingSelectionIntoReclaimedBlockIfNeeded(_ reclaim: BoundaryReclaim) {
        guard let selection = pendingMergedSelection,
              selection.relativeLocation >= reclaim.suffixStartOffset else {
            return
        }

        pendingMergedSelection = PendingMergedSelection(blockIndex: reclaim.nextBlockIndex,
                                                        sourceLineRange: nil,
                                                        sourceLineLocation: nil,
                                                        sourceColumn: nil,
                                                        relativeLocation: selection.relativeLocation - reclaim.suffixStartOffset,
                                                        length: selection.length)
    }

    func lines(fromEditedMergedText text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return [] }

        return normalized.components(separatedBy: "\n")
    }

    func currentMergedSelection(affecting blockIndexes: Set<Int>) -> PendingMergedSelection? {
        guard let textView = mergedTextView else { return nil }
        guard let rangeIndex = mergedTextRangeIndex(at: textView.selectedRange().location) else { return nil }
        let range = mergedTextRanges[rangeIndex]
        guard blockIndexes.contains(range.blockIndex) else { return nil }
        return pendingSelection(from: textView.selectedRange(),
                                in: range,
                                text: textView.string as NSString)
    }

    func pendingSelection(from selection: NSRange,
                                  in range: MergedBlockTextRange,
                                  text: NSString? = nil) -> PendingMergedSelection {
        pendingSelection(from: selection,
                         blockIndex: range.blockIndex,
                         sourceLineRange: range.sourceLineRange,
                         blockRange: range.characterRange,
                         text: text)
    }

    func pendingSelection(from selection: NSRange,
                                  blockIndex: Int,
                                  sourceLineRange: NSRange?,
                                  blockRange: NSRange,
                                  text: NSString? = nil) -> PendingMergedSelection {
        let relativeLocation = min(max(selection.location - blockRange.location, 0), blockRange.length)
        let length = min(selection.length, max(blockRange.length - relativeLocation, 0))
        let sourcePosition = pendingSourcePosition(relativeLocation: relativeLocation,
                                                   sourceLineRange: sourceLineRange,
                                                   blockRange: blockRange,
                                                   text: text)
        return PendingMergedSelection(blockIndex: blockIndex,
                                      sourceLineRange: sourceLineRange,
                                      sourceLineLocation: sourcePosition?.lineLocation,
                                      sourceColumn: sourcePosition?.column,
                                      relativeLocation: relativeLocation,
                                      length: length)
    }

    func pendingSourcePosition(relativeLocation: Int,
                               sourceLineRange: NSRange?,
                               blockRange: NSRange,
                               text: NSString?) -> (lineLocation: Int, column: Int)? {
        guard let sourceLineRange,
              let text,
              NSMaxRange(blockRange) <= text.length else { return nil }

        let safeRelativeLocation = min(max(relativeLocation, 0), blockRange.length)
        let localText = text.substring(with: blockRange) as NSString
        var row = 0
        var lineStart = 0
        var searchLocation = 0

        while searchLocation < safeRelativeLocation {
            let searchRange = NSRange(location: searchLocation,
                                      length: safeRelativeLocation - searchLocation)
            let newline = localText.range(of: "\n", options: [], range: searchRange)
            guard newline.location != NSNotFound else { break }
            row += 1
            lineStart = NSMaxRange(newline)
            searchLocation = lineStart
        }

        return (sourceLineRange.location + row,
                safeRelativeLocation - lineStart)
    }

    func restorePendingMergedSelection(scrollRangeToVisible: Bool = true) {
        guard let selection = pendingMergedSelection else { return }
        pendingMergedSelection = nil
        guard let textView = mergedTextView else {
            AppLogger.info("MERGE_SELECTION_RESTORE result=skipped reason=missing_text_view pending=\(pendingSelectionLog(selection))")
            return
        }
        let selectionBeforeRestore = mergedTextSelectionDetailLog(textView)
        let sourcePositionRange = mergedTextRange(containingSourcePosition: selection)
        let exactRange = mergedTextRanges.first(where: { mergedRange($0, matches: selection) })
        let sameBlockRange = mergedTextRanges.first(where: { $0.blockIndex == selection.blockIndex })
        guard let range = sourcePositionRange ?? exactRange ?? sameBlockRange else {
            AppLogger.info("MERGE_SELECTION_RESTORE result=skipped reason=missing_range pending=\(pendingSelectionLog(selection)) selectionBefore=\(selectionBeforeRestore)")
            return
        }

        let sourceLocation = sourcePositionRange.flatMap {
            characterLocation(forSourcePosition: selection,
                              in: $0,
                              text: textView.string as NSString)
        }
        let restoredLocation: Int
        let match: String
        if let sourceLocation {
            restoredLocation = sourceLocation
            match = "source_position"
        } else {
            let relativeLocation = min(selection.relativeLocation, range.characterRange.length)
            restoredLocation = range.characterRange.location + relativeLocation
            match = exactRange == nil ? "same_block" : "exact"
        }
        let length = min(selection.length, max((textView.string as NSString).length - restoredLocation, 0))
        let restored = NSRange(location: restoredLocation, length: length)
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(restored)
        if scrollRangeToVisible {
            textView.scrollRangeToVisible(restored)
        }
        AppLogger.info("MERGE_SELECTION_RESTORE result=applied match=\(match) scrollToVisible=\(scrollRangeToVisible) pending=\(pendingSelectionLog(selection)) selectionBefore=\(selectionBeforeRestore) targetRange=\(mergedTextRangeLog(range)) restored=\(restored.location):\(restored.length):\(textPositionLog(location: restored.location, in: textView.string as NSString)) selectionAfter=\(mergedTextSelectionDetailLog(textView))")
    }

    func mergedTextRange(containingSourcePosition selection: PendingMergedSelection) -> MergedBlockTextRange? {
        guard let sourceLineLocation = selection.sourceLineLocation else { return nil }
        return mergedTextRanges.first { range in
            guard range.blockIndex == selection.blockIndex,
                  range.isEditable,
                  let sourceLineRange = range.sourceLineRange else { return false }
            return sourceLineLocation >= sourceLineRange.location &&
                sourceLineLocation < NSMaxRange(sourceLineRange)
        }
    }

    func characterLocation(forSourcePosition selection: PendingMergedSelection,
                           in range: MergedBlockTextRange,
                           text: NSString) -> Int? {
        guard let sourceLineLocation = selection.sourceLineLocation,
              let sourceColumn = selection.sourceColumn,
              let sourceLineRange = range.sourceLineRange,
              sourceLineLocation >= sourceLineRange.location,
              sourceLineLocation < NSMaxRange(sourceLineRange),
              NSMaxRange(range.characterRange) <= text.length else {
            return nil
        }

        let targetRow = sourceLineLocation - sourceLineRange.location
        let rangeEnd = NSMaxRange(range.characterRange)
        var lineStart = range.characterRange.location
        if targetRow > 0 {
            for _ in 0..<targetRow {
                guard lineStart < rangeEnd else { return rangeEnd }
                let searchRange = NSRange(location: lineStart, length: rangeEnd - lineStart)
                let newline = text.range(of: "\n", options: [], range: searchRange)
                guard newline.location != NSNotFound else { return rangeEnd }
                lineStart = NSMaxRange(newline)
            }
        }

        let lineEnd: Int
        if lineStart < rangeEnd {
            let searchRange = NSRange(location: lineStart, length: rangeEnd - lineStart)
            let newline = text.range(of: "\n", options: [], range: searchRange)
            lineEnd = newline.location == NSNotFound ? rangeEnd : newline.location
        } else {
            lineEnd = rangeEnd
        }
        return min(lineStart + max(sourceColumn, 0), lineEnd)
    }

    func mergedRange(_ range: MergedBlockTextRange, matches selection: PendingMergedSelection) -> Bool {
        range.blockIndex == selection.blockIndex &&
        sameRange(range.sourceLineRange, selection.sourceLineRange)
    }

    func mergedRange(_ range: MergedBlockTextRange, matches other: MergedBlockTextRange) -> Bool {
        range.blockIndex == other.blockIndex &&
        sameRange(range.characterRange, other.characterRange) &&
        range.isEditable == other.isEditable &&
        sameRange(range.sourceLineRange, other.sourceLineRange)
    }

    func sameRange(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }

    func sameRange(_ lhs: NSRange?, _ rhs: NSRange?) -> Bool {
        switch (lhs, rhs) {
            case let (.some(lhs), .some(rhs)):
                return sameRange(lhs, rhs)
            case (.none, .none):
                return true
            default:
                return false
        }
    }
}
