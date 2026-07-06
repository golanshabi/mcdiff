import AppKit

extension MainWindowController {
    func shouldRefreshRenderPlanInline(for decision: MergedEditRenderDecision) -> Bool {
        decision.reason == "inline_row_count" ||
            decision.reason == "inline_source_line_count"
    }

    func canInlineRenderPlanEdit(edit: PendingMergedEdit,
                                 block: MDBlock,
                                 editedLines: [String]) -> Bool {
        guard edit.ranges.count == 1,
              block.kind == .changed || block.kind == .equal,
              !editedLines.isEmpty else {
            return false
        }

        let maxEditedWidth = editedLines.map(measuredLineWidth).max() ?? 0
        return maxEditedWidth <= sharedMaxContentWidth() + 1
    }

    func refreshRenderedPanesAfterInlineRenderPlanEdit() -> Bool {
        guard let document else { return false }
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        let plan = renderPlan(for: document)
        guard canApplyRenderPlanInline(plan) else { return false }

        for pane in DiffPane.allCases {
            guard let content = plan.panes[pane],
                  let clip = paneTextClipViews[pane]?.first,
                  let column = paneColumnViews[pane] else {
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
        return true
    }

    func refreshRenderedPanesAfterInlineUndoRenderPlanEdit(oldRows: BlockRenderRows) -> Bool {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        guard refreshRenderedPanesAfterInlineRenderPlanEdit() else { return false }
        restorePendingMergedSelection(scrollRangeToVisible: false)
        scroll.contentView.scroll(to: previousVisibleOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        refreshTopInlineRestoreViewportIfNeeded(oldRows)
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
                guard let lineNumberView = paneLineNumberViews[pane],
                      let content = plan.panes[pane] else {
                    return false
                }
                if content.lineNumberControls.isEmpty {
                    guard lineNumberView is NSTextField else { return false }
                } else {
                    guard lineNumberView is PaneLineNumberView else { return false }
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
        }
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
