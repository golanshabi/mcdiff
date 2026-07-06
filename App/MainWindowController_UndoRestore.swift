import AppKit

extension MainWindowController {
    func registerMergedUndo(before snapshots: [MergedBlockSnapshot],
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

    func restoreMergedSnapshots(_ snapshots: [MergedBlockSnapshot],
                                actionName: String,
                                restoreSelection: PendingMergedSelection?) {
        var phases = [TimedPhase]()
        let blockIndexes = snapshots.map(\.blockIndex)
        let (redoSnapshots, redoSnapshotPhase) = timed("redoSnapshots") { self.snapshots(for: blockIndexes) }
        phases.append(redoSnapshotPhase)
        let (redoSelection, redoSelectionPhase) = timed("redoSelection") {
            currentMergedSelection(affecting: Set(blockIndexes))
        }
        phases.append(redoSelectionPhase)
        let selectionToRestore = restoreSelection ?? redoSelection
        let (handledInlineOrRender, restorePhase) = timed("restore") {
            restoreMergedSnapshotsInlineOrRender(snapshots,
                                                 restoreSelection: selectionToRestore,
                                                 actionName: actionName)
        }
        phases.append(restorePhase)
        if handledInlineOrRender {
            finishRestoreMergedSnapshots(phases: phases,
                                         route: "inline_or_render",
                                         actionName: actionName,
                                         snapshots: snapshots,
                                         blockIndexes: blockIndexes,
                                         redoSnapshots: redoSnapshots,
                                         redoSelection: redoSelection,
                                         selectionToRestore: selectionToRestore)
            return
        }

        phases.append(timed("applySnapshots") { apply(snapshots: snapshots) }.1)
        pendingMergedSelection = selectionToRestore
        let (refreshedInline, inlinePhase) = timed("inlineRenderPlan") {
            refreshRenderedPanesAfterInlineUndoRenderPlanEdit(oldRows: nil,
                                                              updateContentWidths: true)
        }
        phases.append(inlinePhase)
        let route: String
        if refreshedInline {
            route = "inline_render_plan"
        } else {
            route = "render"
            phases.append(timed("render") { render(preservingVerticalPosition: true) }.1)
        }
        finishRestoreMergedSnapshots(phases: phases,
                                     route: route,
                                     actionName: actionName,
                                     snapshots: snapshots,
                                     blockIndexes: blockIndexes,
                                     redoSnapshots: redoSnapshots,
                                     redoSelection: redoSelection,
                                     selectionToRestore: selectionToRestore)
    }

    func finishRestoreMergedSnapshots(phases: [TimedPhase],
                                      route: String,
                                      actionName: String,
                                      snapshots: [MergedBlockSnapshot],
                                      blockIndexes: [Int],
                                      redoSnapshots: [MergedBlockSnapshot],
                                      redoSelection: PendingMergedSelection?,
                                      selectionToRestore: PendingMergedSelection?) {
        var phases = phases
        phases.append(timed("updateButtons") { updateButtons() }.1)
        phases.append(timed("registerUndo") {
            registerMergedUndo(before: redoSnapshots,
                               actionName: actionName,
                               restoreSelection: redoSelection)
        }.1)
        logPerformance("restoreMergedSnapshots",
                       phases: phases,
                       metadata: "action=\(logToken(actionName)) route=\(route) snapshots=\(snapshots.count) blocks=\(blockList(blockIndexes)) restoreSelection=\(pendingSelectionLog(selectionToRestore)) selectionAfter=\(mergedTextSelectionLog()) canUndo=\(mergeUndoManager.canUndo) canRedo=\(mergeUndoManager.canRedo)",
                       minimumTotalMilliseconds: 0)
    }

    func restoreMergedSnapshotsInlineOrRender(_ snapshots: [MergedBlockSnapshot],
                                              restoreSelection: PendingMergedSelection?,
                                              actionName: String) -> Bool {
        let restoreStart = DispatchTime.now().uptimeNanoseconds
        var phases = [TimedPhase]()
        func logInlineRestore(route: String,
                              reason: String,
                              snapshot: MergedBlockSnapshot?,
                              extra: String = "") {
            let elapsed = DispatchTime.now().uptimeNanoseconds - restoreStart
            let loggedPhases = phases.isEmpty
                ? [TimedPhase(name: "total", milliseconds: Double(elapsed) / 1_000_000.0)]
                : phases
            let blockText = snapshot.map { String($0.blockIndex) } ?? "nil"
            let extraText = extra.isEmpty ? "" : " \(extra)"
            logPerformance("restoreMergedSnapshotsInline",
                           phases: loggedPhases,
                           metadata: "action=\(logToken(actionName)) route=\(route) reason=\(reason) snapshots=\(snapshots.count) block=\(blockText) restoreSelection=\(pendingSelectionLog(restoreSelection)) selection=\(mergedTextSelectionLog())\(extraText)",
                           minimumTotalMilliseconds: 0)
        }

        guard snapshots.count == 1 else {
            logInlineRestore(route: "skipped",
                             reason: "snapshot_count",
                             snapshot: snapshots.first)
            return false
        }
        guard let snapshot = snapshots.first else {
            logInlineRestore(route: "skipped", reason: "missing_snapshot", snapshot: nil)
            return false
        }
        guard let document else {
            logInlineRestore(route: "skipped", reason: "missing_document", snapshot: snapshot)
            return false
        }
        guard let textView = mergedTextView else {
            logInlineRestore(route: "skipped", reason: "missing_text_view", snapshot: snapshot)
            return false
        }
        guard snapshot.blockIndex >= 0,
              snapshot.blockIndex < document.blocks.count else {
            logInlineRestore(route: "skipped",
                             reason: "invalid_block",
                             snapshot: snapshot,
                             extra: "blocks=\(document.blocks.count)")
            return false
        }
        guard let oldRows = renderedBlockRows[snapshot.blockIndex] else {
            logInlineRestore(route: "skipped", reason: "missing_rows", snapshot: snapshot)
            return false
        }

        let currentText = textView.string as NSString
        let (oldBlockRangeCandidate, displayRangePhase) = timed("displayRange") {
            mergedTextDisplayRange(for: snapshot.blockIndex, in: currentText)
        }
        phases.append(displayRangePhase)
        guard let oldBlockRange = oldBlockRangeCandidate else {
            logInlineRestore(route: "skipped", reason: "missing_display_range", snapshot: snapshot)
            return false
        }

        phases.append(timed("applySnapshots") { apply(snapshots: snapshots) }.1)
        pendingMergedSelection = restoreSelection

        let block = document.blocks[snapshot.blockIndex]
        let (afterRowCount, rowCountPhase) = timed("rowCount") {
            renderedRowCount(for: block, blockIndex: snapshot.blockIndex)
        }
        phases.append(rowCountPhase)
        let (newLinesCandidate, mergedLinesPhase) = timed("mergedLines") {
            renderedMergedLines(for: snapshot.blockIndex)
        }
        phases.append(mergedLinesPhase)
        guard oldRows.rowCount == afterRowCount else {
            if let newLines = newLinesCandidate {
                let ((maxNewWidth, maxSharedWidth), widthPhase) = timed("width") {
                    ((newLines.map(measuredLineWidth).max() ?? 0), sharedMaxContentWidth())
                }
                phases.append(widthPhase)
                let needsWidthUpdate = maxNewWidth > maxSharedWidth + 1
                let (refreshedInline, inlineRenderPlanPhase) = timed("inlineRenderPlan") {
                    refreshRenderedPanesAfterInlineUndoRenderPlanEdit(oldRows: oldRows,
                                                                      updateContentWidths: needsWidthUpdate)
                }
                phases.append(inlineRenderPlanPhase)
                if refreshedInline {
                    logInlineRestore(route: "inline",
                                     reason: "row_count",
                                     snapshot: snapshot,
                                     extra: "rows=\(oldRows.rowCount)->\(afterRowCount)")
                    return true
                }
            }
            phases.append(timed("render") { render(preservingVerticalPosition: true) }.1)
            logInlineRestore(route: "render",
                             reason: "row_count",
                             snapshot: snapshot,
                             extra: "rows=\(oldRows.rowCount)->\(afterRowCount)")
            return true
        }
        guard let newLines = newLinesCandidate else {
            phases.append(timed("render") { render(preservingVerticalPosition: true) }.1)
            logInlineRestore(route: "render", reason: "missing_lines", snapshot: snapshot)
            return true
        }

        let ((maxNewWidth, maxSharedWidth), widthPhase) = timed("width") {
            ((newLines.map(measuredLineWidth).max() ?? 0), sharedMaxContentWidth())
        }
        phases.append(widthPhase)
        guard maxNewWidth <= maxSharedWidth + 1 else {
            let (refreshedInline, inlineRenderPlanPhase) = timed("inlineRenderPlan") {
                refreshRenderedPanesAfterInlineUndoRenderPlanEdit(oldRows: oldRows,
                                                                  updateContentWidths: true)
            }
            phases.append(inlineRenderPlanPhase)
            if refreshedInline {
                logInlineRestore(route: "inline",
                                 reason: "width",
                                 snapshot: snapshot,
                                 extra: "editedWidth=\(format(maxNewWidth)) sharedWidth=\(format(maxSharedWidth))")
                return true
            }
            phases.append(timed("render") { render(preservingVerticalPosition: true) }.1)
            logInlineRestore(route: "render",
                             reason: "width",
                             snapshot: snapshot,
                             extra: "editedWidth=\(format(maxNewWidth)) sharedWidth=\(format(maxSharedWidth))")
            return true
        }

        let newText = newLines.joined(separator: "\n")
        guard NSMaxRange(oldBlockRange) <= currentText.length else {
            phases.append(timed("render") { render(preservingVerticalPosition: true) }.1)
            logInlineRestore(route: "render",
                             reason: "range",
                             snapshot: snapshot,
                             extra: "range=\(oldBlockRange.location):\(oldBlockRange.length) textLength=\(currentText.length)")
            return true
        }

        phases.append(timed("replaceText") {
            textView.textStorage?.replaceCharacters(in: oldBlockRange, with: newText)
            (textView.superview as? PaneTextClipView)?
                .refreshTextLayout(afterReplacing: oldBlockRange,
                                   replacementText: newText)
        }.1)
        let (plan, renderPlanPhase) = timed("renderPlan") { renderPlan(for: document) }
        phases.append(renderPlanPhase)
        phases.append(timed("applyPlan") {
            mergedTextRanges = plan.mergedTextRanges
            renderedBlockRows = plan.blockRows
            updatePaneBackgroundRuns(for: snapshot.blockIndex)
        }.1)
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        phases.append(timed("restoreSelection") {
            restorePendingMergedSelection(scrollRangeToVisible: false)
        }.1)
        phases.append(timed("restoreViewport") {
            scroll.contentView.scroll(to: previousVisibleOrigin)
            scroll.reflectScrolledClipView(scroll.contentView)
            refreshTopInlineRestoreViewportIfNeeded(oldRows)
        }.1)
        logInlineRestore(route: "inline",
                         reason: "ok",
                         snapshot: snapshot,
                         extra: "rows=\(oldRows.rowCount) chars=\(oldBlockRange.length)->\((newText as NSString).length)")
        return true
    }

    func refreshTopInlineRestoreViewportIfNeeded(_ rows: BlockRenderRows) {
        guard rows.startRow == 0 else { return }

        stack.needsLayout = true
        stack.needsDisplay = true
        scroll.documentView?.needsDisplay = true
        scroll.contentView.needsDisplay = true
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded()
        scroll.contentView.displayIfNeeded()
        scroll.documentView?.displayIfNeeded()
        scroll.displayIfNeeded()
    }

    func mergedTextDisplayRange(for blockIndex: Int, in text: NSString) -> NSRange? {
        guard let rows = renderedBlockRows[blockIndex],
              rows.startRow >= 0,
              rows.rowCount > 0 else {
            return nil
        }

        let targetStartRow = rows.startRow
        let targetEndRow = rows.startRow + rows.rowCount
        var rowStarts = [0]
        var searchLocation = 0
        while searchLocation < text.length && rowStarts.count <= targetEndRow {
            let range = NSRange(location: searchLocation, length: text.length - searchLocation)
            let newline = text.range(of: "\n", options: [], range: range)
            guard newline.location != NSNotFound else { break }
            searchLocation = NSMaxRange(newline)
            rowStarts.append(searchLocation)
        }

        guard targetStartRow < rowStarts.count else { return nil }

        let location = rowStarts[targetStartRow]
        let end: Int
        if targetEndRow < rowStarts.count {
            end = max(rowStarts[targetEndRow] - 1, location)
        } else {
            end = text.length
        }
        return NSRange(location: location, length: max(end - location, 0))
    }

    func renderedMergedLines(for blockIndex: Int) -> [String]? {
        guard let document,
              blockIndex >= 0,
              blockIndex < document.blocks.count else {
            return nil
        }

        let block = document.blocks[blockIndex]
        let displayed = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map {
            ($0, displayedContent(for: block, blockIndex: blockIndex, pane: $0, mergedStartLine: 1))
        })
        let rowCount = renderRowCount(for: block, displayed: displayed)
        guard var lines = displayed[.merged]?.lines else { return nil }
        lines = mergedContentLines(for: block, lines: lines)
        if lines.count > rowCount {
            lines = Array(lines.prefix(rowCount))
        }
        if lines.count < rowCount {
            lines.append(contentsOf: Array(repeating: "", count: rowCount - lines.count))
        }
        return lines
    }
}
