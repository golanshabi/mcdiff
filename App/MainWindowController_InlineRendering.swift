import AppKit

extension MainWindowController {
    func shouldRefreshRenderPlanInline(for decision: MergedEditRenderDecision) -> Bool {
        decision.reason.hasPrefix("inline_")
    }

    func shouldUpdateContentWidthsInline(for decision: MergedEditRenderDecision) -> Bool {
        decision.reason.contains("width")
    }

    func canInlineRenderPlanStructureEdit(edit: PendingMergedEdit,
                                          block: MDBlock,
                                          editedLines: [String]) -> Bool {
        guard edit.ranges.count == 1,
              block.kind == .changed || block.kind == .equal,
              !editedLines.isEmpty else {
            return false
        }
        return true
    }

    func canInlineRenderPlanEdit(edit: PendingMergedEdit,
                                 block: MDBlock,
                                 editedLines: [String]) -> Bool {
        guard canInlineRenderPlanStructureEdit(edit: edit,
                                               block: block,
                                               editedLines: editedLines) else {
            return false
        }

        let maxEditedWidth = editedLines.map(measuredLineWidth).max() ?? 0
        return maxEditedWidth <= sharedMaxContentWidth() + 1
    }

    func refreshRenderedPanesAfterInlineRenderPlanEdit(updateContentWidths: Bool = false) -> Bool {
        guard let document else { return false }
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        let pendingBeforeRefresh = pendingMergedSelection
        let selectionBeforeRefresh = mergedTextSelectionDetailLog()
        let rangeBeforeRefresh = mergedTextRangeAtSelectionLog()
        let oldRangeCount = mergedTextRanges.count
        let oldRowCount = renderedBlockRows.count
        let plan = renderPlan(for: document)
        if updateContentWidths {
            updatePaneContentWidths(for: plan)
        }
        let exactPlanRange = pendingBeforeRefresh.flatMap { pending in
            plan.mergedTextRanges.first(where: { mergedRange($0, matches: pending) })
        }
        let sameBlockPlanRange = pendingBeforeRefresh.flatMap { pending in
            plan.mergedTextRanges.first(where: { $0.blockIndex == pending.blockIndex })
        }
        guard canApplyRenderPlanInline(plan) else {
            if pendingBeforeRefresh != nil {
                AppLogger.info("MERGE_INLINE_REFRESH result=skipped reason=can_apply updateWidths=\(updateContentWidths) pending=\(pendingSelectionLog(pendingBeforeRefresh)) selectionBefore=\(selectionBeforeRefresh) rangeBefore=\(rangeBeforeRefresh) exactPlanRange=\(mergedTextRangeLog(exactPlanRange)) sameBlockPlanRange=\(mergedTextRangeLog(sameBlockPlanRange))")
            }
            return false
        }

        for pane in DiffPane.allCases {
            guard let content = plan.panes[pane],
                  let clip = paneTextClipViews[pane]?.first,
                  let column = paneColumnViews[pane] else {
                if pendingBeforeRefresh != nil {
                    AppLogger.info("MERGE_INLINE_REFRESH result=skipped reason=missing_pane pane=\(pane.identifier) updateWidths=\(updateContentWidths) pending=\(pendingSelectionLog(pendingBeforeRefresh)) selectionBefore=\(selectionBeforeRefresh) rangeBefore=\(rangeBeforeRefresh)")
                }
                return false
            }

            clip.replaceText(content.textLines.joined(separator: "\n"),
                             preserveSelection: pane == .merged)
            column.backgroundRuns = content.backgroundRuns
            if pane != .merged {
                updateLineNumberView(for: pane, content: content)
            }
        }

        guard updatePickButtonColumns(for: plan) else { return false }

        mergedTextRanges = plan.mergedTextRanges
        renderedBlockRows = plan.blockRows
        refreshPaneViewportWidths()
        if let textView = mergedTextView {
            view.window?.makeFirstResponder(textView)
        }
        markInlineRenderPlanViewsDirty()
        scroll.contentView.scroll(to: previousVisibleOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        if pendingBeforeRefresh != nil {
            AppLogger.info("MERGE_INLINE_REFRESH result=applied updateWidths=\(updateContentWidths) pending=\(pendingSelectionLog(pendingBeforeRefresh)) selectionBefore=\(selectionBeforeRefresh) selectionAfter=\(mergedTextSelectionDetailLog()) rangeBefore=\(rangeBeforeRefresh) rangeAfter=\(mergedTextRangeAtSelectionLog()) exactPlanRange=\(mergedTextRangeLog(exactPlanRange)) sameBlockPlanRange=\(mergedTextRangeLog(sameBlockPlanRange)) ranges=\(oldRangeCount)->\(mergedTextRanges.count) rows=\(oldRowCount)->\(renderedBlockRows.count) scrollY=\(format(previousVisibleOrigin.y))->\(format(scroll.contentView.bounds.origin.y))")
        }
        return true
    }

    func refreshRenderedPanesAfterInlineMergedEdit(updateContentWidths: Bool = false) -> Bool {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        guard refreshRenderedPanesAfterInlineRenderPlanEdit(updateContentWidths: updateContentWidths) else { return false }
        restorePendingMergedSelection(scrollRangeToVisible: false)
        scroll.contentView.scroll(to: previousVisibleOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    func refreshRenderedPanesAfterInlineUndoRenderPlanEdit(oldRows: BlockRenderRows?,
                                                           updateContentWidths: Bool = false) -> Bool {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        guard refreshRenderedPanesAfterInlineRenderPlanEdit(updateContentWidths: updateContentWidths) else { return false }
        restorePendingMergedSelection(scrollRangeToVisible: false)
        scroll.contentView.scroll(to: previousVisibleOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        if let oldRows {
            refreshTopInlineRestoreViewportIfNeeded(oldRows)
        }
        return true
    }

    func canApplyRenderPlanInline(_ plan: RenderPlan) -> Bool {
        for pane in DiffPane.allCases {
            guard paneTextClipViews[pane]?.count == 1,
                  paneColumnViews[pane] != nil,
                  plan.panes[pane] != nil else {
                return false
            }

            if pane != .merged {
                guard paneLineNumberViews[pane] != nil,
                      plan.panes[pane] != nil else {
                    return false
                }
            }
        }

        guard let table = stack.arrangedSubviews.first as? NSStackView,
              table.arrangedSubviews.count == 5,
              let leftPickColumn = table.arrangedSubviews[1] as? NSStackView,
              let rightPickColumn = table.arrangedSubviews[3] as? NSStackView,
              leftPickColumn.arrangedSubviews.count == plan.blockSlots.count,
              rightPickColumn.arrangedSubviews.count == plan.blockSlots.count else {
            return false
        }

        return true
    }

    func updateLineNumberView(for pane: DiffPane, content: PaneRenderContent) {
        guard let view = paneLineNumberViews[pane] else { return }

        if content.lineNumberControls.isEmpty,
           let field = view as? NSTextField {
            field.attributedStringValue = attributedLineNumberText(content.lineNumberLines.joined(separator: "\n"))
            field.setAccessibilityLabel(content.lineNumberLines.joined(separator: "\n"))
            field.needsDisplay = true
        } else if let numbers = view as? PaneLineNumberView {
            numbers.update(lineNumberLines: content.lineNumberLines,
                           controls: content.lineNumberControls)
        } else {
            replaceLineNumberView(for: pane, content: content, previousView: view)
        }
    }

    func replaceLineNumberView(for pane: DiffPane,
                               content: PaneRenderContent,
                               previousView: NSView) {
        guard let stack = previousView.superview as? NSStackView else { return }
        let index = stack.arrangedSubviews.firstIndex(of: previousView) ?? 0
        let replacement = makeLineNumberView(for: pane, content: content, identifier: previousView.identifier)
        stack.removeArrangedSubview(previousView)
        previousView.removeFromSuperview()
        stack.insertArrangedSubview(replacement, at: index)
        paneLineNumberViews[pane] = replacement
    }

    func makeLineNumberView(for pane: DiffPane,
                            content: PaneRenderContent,
                            identifier: NSUserInterfaceItemIdentifier?) -> NSView {
        if content.lineNumberControls.isEmpty {
            let numbers = NSTextField(labelWithString: "")
            numbers.identifier = identifier
            numbers.attributedStringValue = attributedLineNumberText(content.lineNumberLines.joined(separator: "\n"))
            numbers.alignment = .right
            numbers.textColor = .secondaryLabelColor
            numbers.font = lineNumberFont
            numbers.lineBreakMode = .byClipping
            numbers.maximumNumberOfLines = 0
            numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
            return numbers
        }

        let numbers = PaneLineNumberView(lineNumberLines: content.lineNumberLines,
                                         controls: content.lineNumberControls,
                                         font: lineNumberFont,
                                         lineHeight: lineHeight,
                                         clickHandler: { [weak self] blockIndex, action in
                                             self?.expandCompactContext(blockIndex: blockIndex, action: action)
                                         })
        numbers.identifier = identifier
        numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
        return numbers
    }

    func updatePickButtonColumns(for plan: RenderPlan) -> Bool {
        guard let table = stack.arrangedSubviews.first as? NSStackView,
              table.arrangedSubviews.count == 5,
              let leftPickColumn = table.arrangedSubviews[1] as? NSStackView,
              let rightPickColumn = table.arrangedSubviews[3] as? NSStackView else {
            return false
        }

        updatePickButtonColumn(leftPickColumn, slots: plan.blockSlots)
        updatePickButtonColumn(rightPickColumn, slots: plan.blockSlots)
        return true
    }

    func updatePickButtonColumn(_ column: NSStackView, slots: [BlockRenderSlot]) {
        for (view, slot) in zip(column.arrangedSubviews, slots) {
            setHeight(CGFloat(slot.rowCount) * lineHeight, on: view)
        }
    }

    func setHeight(_ height: CGFloat, on view: NSView) {
        if let constraint = view.constraints.first(where: { constraint in
            constraint.firstItem === view &&
                constraint.firstAttribute == .height &&
                constraint.secondItem == nil
        }) {
            constraint.constant = height
        } else {
            view.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        view.needsLayout = true
    }

    func markInlineRenderPlanViewsDirty() {
        stack.needsLayout = true
        stack.needsDisplay = true
        scroll.documentView?.needsLayout = true
        scroll.documentView?.needsDisplay = true
        scroll.contentView.needsDisplay = true
        view.needsLayout = true
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded()
        scroll.contentView.displayIfNeeded()
        scroll.documentView?.displayIfNeeded()
    }
}
