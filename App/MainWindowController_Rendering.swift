import AppKit

extension MainWindowController {
    func render(preservingVerticalPosition: Bool) {
        let previousVisibleOrigin = scroll.contentView.bounds.origin
        var phases = [TimedPhase]()
        phases.append(timed("contentWidths") { updatePaneContentWidths() }.1)
        phases.append(timed("clearViews") {
            paneTextClipViews = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, [PaneTextClipView]()) })
            paneColumnViews = [:]
            paneLineNumberViews = [:]
            renderedBlockRows = [:]
            mergedTextView = nil
            mergedTextRanges = []
            stack.arrangedSubviews.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }.1)
        guard let document else {
            logPerformance("render", phases: phases, metadata: "document=none", minimumTotalMilliseconds: 75)
            return
        }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        let (plan, planPhase) = timed("renderPlan") { renderPlan(for: document) }
        phases.append(planPhase)
        mergedTextRanges = plan.mergedTextRanges
        renderedBlockRows = plan.blockRows
        let (_, tablePhase) = timed("views") { stack.addArrangedSubview(diffTableView(for: plan)) }
        phases.append(tablePhase)
        phases.append(timed("refreshWidths") { refreshPaneViewportWidths() }.1)
        if preservingVerticalPosition {
            phases.append(timed("restoreScroll") {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: previousVisibleOrigin.y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }.1)
        }
        phases.append(timed("restoreSelection") { restorePendingMergedSelection() }.1)
        logPerformance("render",
                       phases: phases,
                       metadata: "blocks=\(document.blocks.count) rows=\(plan.totalRows) preserving=\(preservingVerticalPosition)",
                       minimumTotalMilliseconds: 75)
    }

    func diffTableView(for plan: RenderPlan) -> NSView {
        let row = NSStackView()
        row.identifier = NSUserInterfaceItemIdentifier("diffTable")
        row.orientation = .horizontal
        row.spacing = 0

        let leftPane = paneColumnView(for: plan, pane: .left)
        let mergedPane = paneColumnView(for: plan, pane: .merged)
        let rightPane = paneColumnView(for: plan, pane: .right)

        row.addArrangedSubview(leftPane)
        row.addArrangedSubview(pickButtonColumn(for: plan.blockSlots, picksLeft: true))
        row.addArrangedSubview(mergedPane)
        row.addArrangedSubview(pickButtonColumn(for: plan.blockSlots, picksLeft: false))
        row.addArrangedSubview(rightPane)
        NSLayoutConstraint.activate([
            leftPane.widthAnchor.constraint(equalTo: mergedPane.widthAnchor),
            rightPane.widthAnchor.constraint(equalTo: mergedPane.widthAnchor)
        ])
        return row
    }

    func pickButtonColumn(for slots: [BlockRenderSlot], picksLeft: Bool) -> NSView {
        let column = NSStackView()
        column.identifier = NSUserInterfaceItemIdentifier(picksLeft ? "leftPickButtonColumn" : "rightPickButtonColumn")
        column.orientation = .vertical
        column.spacing = 0
        column.widthAnchor.constraint(equalToConstant: pickButtonSlotWidth).isActive = true

        for slot in slots {
            column.addArrangedSubview(pickButtonSlot(slot.block, picksLeft: picksLeft, rowCount: slot.rowCount))
        }

        return column
    }

    func pickButtonSlot(_ block: MDBlock, picksLeft: Bool, rowCount: Int) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("pickButtonSlot")
        view.heightAnchor.constraint(equalToConstant: CGFloat(rowCount) * lineHeight).isActive = true

        if block.kind == .changed && !isGitDiffPreview {
            let button = PickButton(title: picksLeft ? "→" : "←", target: self, action: #selector(pick(_:)))
            button.block = block
            button.picksLeft = picksLeft
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 18, weight: .medium)
            button.toolTip = picksLeft ? "Use Left" : "Use Right"
            button.setAccessibilityLabel(picksLeft ? "Use Left" : "Use Right")
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 24)
            ])
        }

        return view
    }

    func paneColumnView(for plan: RenderPlan, pane: DiffPane) -> NSView {
        let content = plan.panes[pane] ?? PaneRenderContent()
        let view = PaneColumnView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier(for: pane))
        view.lineHeight = lineHeight
        view.backgroundRuns = content.backgroundRuns
        paneColumnViews[pane] = view
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let layout = NSStackView()
        layout.orientation = .horizontal
        layout.spacing = paneContentSpacing
        layout.alignment = .top
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.setContentHuggingPriority(.defaultLow, for: .horizontal)
        layout.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: paneInset),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -paneInset)
        ])

        if pane != .merged {
            let numberIdentifier = NSUserInterfaceItemIdentifier("\(identifier(for: pane))LineNumbers")
            if content.lineNumberControls.isEmpty {
                let numbers = NSTextField(labelWithString: "")
                numbers.identifier = numberIdentifier
                numbers.attributedStringValue = attributedLineNumberText(content.lineNumberLines.joined(separator: "\n"))
                numbers.alignment = .right
                numbers.textColor = .secondaryLabelColor
                numbers.font = lineNumberFont
                numbers.lineBreakMode = .byClipping
                numbers.maximumNumberOfLines = 0
                numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
                layout.addArrangedSubview(numbers)
                paneLineNumberViews[pane] = numbers
            } else {
                let numbers = PaneLineNumberView(lineNumberLines: content.lineNumberLines,
                                                 controls: content.lineNumberControls,
                                                 font: lineNumberFont,
                                                 lineHeight: lineHeight,
                                                 clickHandler: { [weak self] blockIndex, action in
                                                     self?.expandCompactContext(blockIndex: blockIndex, action: action)
                                                 })
                numbers.identifier = numberIdentifier
                numbers.widthAnchor.constraint(equalToConstant: lineNumberWidth).isActive = true
                layout.addArrangedSubview(numbers)
                paneLineNumberViews[pane] = numbers
            }
        }

        let text = content.textLines.joined(separator: "\n")
        let clip = PaneTextClipView(text: text,
                                    pane: pane,
                                    font: paneTextFont,
                                    lineHeight: lineHeight,
                                    isEditable: pane == .merged && !isGitDiffPreview,
                                    textDelegate: pane == .merged && !isGitDiffPreview ? self : nil,
                                    undoHandler: { [weak self] in self?.performUndo() },
                                    redoHandler: { [weak self] in self?.performRedo() })
        clip.delegate = self
        clip.textOffset = paneStates[pane]?.offset ?? 0
        paneTextClipViews[pane, default: []].append(clip)
        if pane == .merged {
            mergedTextView = clip.editableTextView
        }
        layout.addArrangedSubview(clip)

        return view
    }

    func renderPlan(for document: MDDocument) -> RenderPlan {
        var panes = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map { ($0, PaneRenderContent()) })
        var slots = [BlockRenderSlot]()
        var blockRows = [Int: BlockRenderRows]()
        var mergedRanges = [MergedBlockTextRange]()
        var totalRows = 0
        var mergedStartLine = 1
        var mergedCharacterLocation = 0
        var mergedHasPreviousLine = false

        for (blockIndex, block) in document.blocks.enumerated() {
            let displayed = Dictionary(uniqueKeysWithValues: DiffPane.allCases.map {
                ($0, displayedContent(for: block,
                                       blockIndex: blockIndex,
                                       pane: $0,
                                       mergedStartLine: mergedStartLine))
            })
            let rowCount = renderRowCount(for: block, displayed: displayed)

            for pane in DiffPane.allCases {
                guard let display = displayed[pane] else { continue }
                var lines = display.lines
                if pane == .merged {
                    lines = mergedContentLines(for: block, lines: lines)
                }
                if lines.count > rowCount {
                    lines = Array(lines.prefix(rowCount))
                }
                if lines.count < rowCount {
                    lines.append(contentsOf: Array(repeating: "", count: rowCount - lines.count))
                }
                if pane == .merged {
                    let rangeStart = mergedCharacterLocation + (mergedHasPreviousLine ? 1 : 0)
                    let segments = display.mergedRangeSegments.isEmpty
                        ? [MergedRangeSegment(rowRange: NSRange(location: 0, length: lines.count),
                                              isEditable: display.isEditable,
                                              sourceLineRange: display.isEditable ? NSRange(location: 0, length: display.lines.count) : nil)]
                        : display.mergedRangeSegments
                    for segment in segments {
                        let boundedStart = min(max(segment.rowRange.location, 0), lines.count)
                        let boundedEnd = min(max(NSMaxRange(segment.rowRange), boundedStart), lines.count)
                        let segmentLines = Array(lines[boundedStart..<boundedEnd])
                        let characterRange = NSRange(location: rangeStart + characterOffset(forRow: boundedStart, in: lines),
                                                     length: characterLength(for: segmentLines))
                        mergedRanges.append(MergedBlockTextRange(blockIndex: blockIndex,
                                                                 characterRange: characterRange,
                                                                 isEditable: segment.isEditable,
                                                                 sourceLineRange: segment.sourceLineRange))
                    }
                    if !lines.isEmpty {
                        if mergedHasPreviousLine {
                            mergedCharacterLocation += 1
                        }
                        mergedCharacterLocation += characterLength(for: lines)
                        mergedHasPreviousLine = true
                    }
                }
                panes[pane]?.textLines.append(contentsOf: lines)
                if pane != .merged {
                    let numbers = display.lineNumberLines ?? lineNumberLines(lines: display.lines,
                                                                              start: display.start,
                                                                              rowCount: rowCount)
                    let lineNumberStartRow = panes[pane]?.lineNumberLines.count ?? totalRows
                    if numbers.count < rowCount {
                        panes[pane]?.lineNumberLines.append(contentsOf: numbers)
                        panes[pane]?.lineNumberLines.append(contentsOf: Array(repeating: "", count: rowCount - numbers.count))
                    } else {
                        panes[pane]?.lineNumberLines.append(contentsOf: Array(numbers.prefix(rowCount)))
                    }
                    for (relativeRow, control) in display.lineNumberControls {
                        guard relativeRow >= 0, relativeRow < rowCount else { continue }
                        panes[pane]?.lineNumberControls[lineNumberStartRow + relativeRow] = control
                    }
                }
                for range in display.collapsedRowRanges {
                    let boundedLength = min(range.length, max(rowCount - range.location, 0))
                    guard range.location >= 0, boundedLength > 0 else { continue }
                    panes[pane]?.backgroundRuns.append(PaneBackgroundRun(startRow: totalRows + range.location,
                                                                         rowCount: boundedLength,
                                                                         color: collapsedContextBackgroundColor))
                }
                if let color = backgroundColor(for: block, pane: pane) {
                    panes[pane]?.backgroundRuns.append(PaneBackgroundRun(startRow: totalRows,
                                                                         rowCount: rowCount,
                                                                         color: color))
                }
            }

            slots.append(BlockRenderSlot(block: block, rowCount: rowCount))
            blockRows[blockIndex] = BlockRenderRows(startRow: totalRows, rowCount: rowCount)
            totalRows += rowCount
            mergedStartLine += mergedOutputLineCount(for: block)
        }

        if totalRows == 0 {
            for pane in DiffPane.allCases {
                panes[pane]?.textLines.append("")
                if pane != .merged {
                    panes[pane]?.lineNumberLines.append("")
                }
            }
            totalRows = 1
        }

        return RenderPlan(panes: panes,
                          blockSlots: slots,
                          blockRows: blockRows,
                          mergedTextRanges: mergedRanges,
                          totalRows: totalRows)
    }

    func mergedContentLines(for block: MDBlock, lines: [String]) -> [String] {
        if block.kind == .changed && lines.isEmpty {
            return [""]
        }
        return lines
    }

    func characterLength(for lines: [String]) -> Int {
        guard let first = lines.first else { return 0 }
        return lines.dropFirst().reduce((first as NSString).length) { length, line in
            length + 1 + (line as NSString).length
        }
    }

    func characterOffset(forRow row: Int, in lines: [String]) -> Int {
        guard row > 0 else { return 0 }
        let prefixLines = Array(lines.prefix(row))
        return characterLength(for: prefixLines) + 1
    }

    func renderRowCount(for block: MDBlock,
                                displayed: [DiffPane: PaneDisplay]) -> Int {
        max(displayed.values.map(\.lines.count).max() ?? 0, 1)
    }

    func identifier(for pane: DiffPane) -> String {
        pane.identifier
    }

    func backgroundColor(for block: MDBlock, pane: DiffPane) -> NSColor? {
        guard block.kind == .changed else { return nil }

        switch pane {
            case .left:
                return block.pick == .left ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemRed.withAlphaComponent(0.16)
            case .merged:
                if block.pick == .unpicked {
                    return NSColor.systemOrange.withAlphaComponent(0.16)
                }
                if block.pick == .manual {
                    return NSColor.systemPurple.withAlphaComponent(0.14)
                }
                return NSColor.systemBlue.withAlphaComponent(0.10)
            case .right:
                return block.pick == .right ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemGreen.withAlphaComponent(0.16)
        }
    }

    func displayedLines(for block: MDBlock, pane: DiffPane, mergedStartLine: Int) -> (lines: [String], start: Int?) {
        switch pane {
            case .left:
                return (block.leftLines ?? [], block.leftStartLine)
            case .right:
                return (block.rightLines ?? [], block.rightStartLine)
            case .merged:
                return mergedLines(for: block, start: mergedStartLine)
        }
    }

    func displayedContent(for block: MDBlock,
                                  blockIndex: Int,
                                  pane: DiffPane,
                                  mergedStartLine: Int) -> PaneDisplay {
        let full = displayedLines(for: block, pane: pane, mergedStartLine: mergedStartLine)
        let editable = !rendersConflictContextOnly || block.kind == .changed
        guard rendersConflictContextOnly, block.kind == .equal else {
            return PaneDisplay(lines: full.lines,
                               start: full.start,
                               lineNumberLines: nil,
                               lineNumberControls: [:],
                               mergedRangeSegments: [
                                   MergedRangeSegment(rowRange: NSRange(location: 0, length: full.lines.count),
                                                      isEditable: editable,
                                                      sourceLineRange: block.kind == .equal && editable
                                                          ? NSRange(location: 0, length: full.lines.count)
                                                          : nil)
                               ],
                               isEditable: editable,
                               collapsedRowRanges: [])
        }

        let compacted = compactedContextLines(full.lines, start: full.start, blockIndex: blockIndex)
        return PaneDisplay(lines: compacted.lines,
                           start: nil,
                           lineNumberLines: compacted.lineNumberLines,
                           lineNumberControls: compacted.lineNumberControls,
                           mergedRangeSegments: compacted.mergedRangeSegments,
                           isEditable: !compacted.collapsed,
                           collapsedRowRanges: compacted.collapsedRowRanges)
    }

    var collapsedContextBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.14)
    }

    func compactedContextLines(_ lines: [String],
                                       start: Int?,
                                       blockIndex: Int) -> (lines: [String],
                                                            lineNumberLines: [String],
                                                            lineNumberControls: [Int: PaneLineNumberControl],
                                                            mergedRangeSegments: [MergedRangeSegment],
                                                            collapsed: Bool,
                                                            collapsedRowRanges: [NSRange]) {
        let expansion = normalizedCompactContextExpansion(compactContextExpansions[blockIndex] ?? initialCompactContextExpansion(lineCount: lines.count),
                                                          lineCount: lines.count)
        let prefixCount = expansion.prefixLineCount
        let suffixCount = expansion.suffixLineCount
        if prefixCount + suffixCount >= lines.count {
            return (lines,
                    concreteLineNumbers(start: start, indexes: Array(lines.indices)),
                    [:],
                    [MergedRangeSegment(rowRange: NSRange(location: 0, length: lines.count),
                                        isEditable: true,
                                        sourceLineRange: NSRange(location: 0, length: lines.count))],
                    false,
                    [])
        }

        let prefixIndexes = Array(lines.indices.prefix(prefixCount))
        let suffixIndexes = Array(lines.indices.suffix(suffixCount))
        let controlLines = ["", "⋯", ""]
        var compactedLines = prefixIndexes.map { lines[$0] }
        let collapsedStart = compactedLines.count
        compactedLines.append(contentsOf: controlLines)
        compactedLines.append(contentsOf: suffixIndexes.map { lines[$0] })

        var numbers = concreteLineNumbers(start: start, indexes: prefixIndexes)
        numbers.append(contentsOf: Array(repeating: "", count: controlLines.count))
        numbers.append(contentsOf: concreteLineNumbers(start: start, indexes: suffixIndexes))

        let controls = [
            collapsedStart: PaneLineNumberControl(symbol: "↑", blockIndex: blockIndex, action: .expandAbove),
            collapsedStart + 1: PaneLineNumberControl(symbol: "↕", blockIndex: blockIndex, action: .expandAll),
            collapsedStart + 2: PaneLineNumberControl(symbol: "↓", blockIndex: blockIndex, action: .expandBelow)
        ]
        let segments = [
            MergedRangeSegment(rowRange: NSRange(location: 0, length: prefixCount),
                               isEditable: true,
                               sourceLineRange: NSRange(location: 0, length: prefixCount)),
            MergedRangeSegment(rowRange: NSRange(location: collapsedStart, length: controlLines.count),
                               isEditable: false,
                               sourceLineRange: nil),
            MergedRangeSegment(rowRange: NSRange(location: collapsedStart + controlLines.count, length: suffixCount),
                               isEditable: true,
                               sourceLineRange: NSRange(location: lines.count - suffixCount, length: suffixCount))
        ]
        return (compactedLines,
                numbers,
                controls,
                segments,
                true,
                [NSRange(location: collapsedStart, length: controlLines.count)])
    }

    func initialCompactContextExpansion(lineCount: Int) -> CompactContextExpansion {
        CompactContextExpansion(prefixLineCount: min(gitContextLineCount, lineCount),
                                suffixLineCount: min(gitContextLineCount, lineCount))
    }

    func concreteLineNumbers(start: Int?, indexes: [Int]) -> [String] {
        guard let start, start > 0 else {
            return Array(repeating: "", count: indexes.count)
        }

        return indexes.map { "\(start + $0)" }
    }

    func lineNumberLines(lines: [String], start: Int?, rowCount: Int) -> [String] {
        guard let start, start > 0 else {
            return Array(repeating: "", count: rowCount)
        }

        return (0..<rowCount).map { index in
            guard index < lines.count, !lines[index].isEmpty else { return "" }
            return "\(start + index)"
        }
    }

    func attributedLineNumberText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        return NSAttributedString(string: text, attributes: [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ])
    }

    func mergedLines(for block: MDBlock, start: Int) -> (lines: [String], start: Int?) {
        if block.kind == .equal {
            if block.pick == .manual {
                return (block.manualLines ?? [], start)
            }
            return (block.leftLines ?? [], start)
        }

        switch block.pick {
            case .left:
                return (block.leftLines ?? [], start)
            case .right:
                return (block.rightLines ?? [], start)
            case .manual:
                return (block.manualLines ?? [], start)
            case .unpicked:
                return ([], nil)
            @unknown default:
                return ([], nil)
        }
    }

    func mergedOutputLineCount(for block: MDBlock) -> Int {
        if block.kind == .equal {
            if block.pick == .manual {
                return block.manualLines?.count ?? 0
            }
            return block.leftLines?.count ?? 0
        }

        switch block.pick {
            case .left:
                return block.leftLines?.count ?? 0
            case .right:
                return block.rightLines?.count ?? 0
            case .manual:
                return block.manualLines?.count ?? 0
            case .unpicked:
                return 0
            @unknown default:
                return 0
        }
    }

    @objc func pick(_ sender: PickButton) {
        guard let block = sender.block else { return }
        if let blockIndex = document?.blocks.firstIndex(where: { $0 === block }) {
            registerMergedUndo(before: snapshots(for: [blockIndex]),
                               actionName: sender.picksLeft ? "Use Left" : "Use Right",
                               restoreSelection: currentMergedSelection(affecting: [blockIndex]))
        }
        block.pick = sender.picksLeft ? .left : .right
        block.manualLines = []
        AppLogger.info("Picked \(sender.picksLeft ? "left" : "right") for changed block left_start=\(block.leftStartLine) right_start=\(block.rightStartLine)")
        if !refreshRenderedPanesAfterInlineRenderPlanEdit(updateContentWidths: true) {
            render(preservingVerticalPosition: true)
        }
        updateButtons()
    }

    func expandCompactContext(blockIndex: Int, action: CollapsedContextAction) {
        guard let document,
              blockIndex >= 0,
              blockIndex < document.blocks.count else {
            return
        }

        let block = document.blocks[blockIndex]
        let lineCount = displayedLines(for: block, pane: .merged, mergedStartLine: 1).lines.count
        guard lineCount > 0 else { return }

        var expansion = compactContextExpansions[blockIndex] ?? initialCompactContextExpansion(lineCount: lineCount)
        expansion = normalizedCompactContextExpansion(expansion, lineCount: lineCount)
        let hiddenCount = max(lineCount - expansion.prefixLineCount - expansion.suffixLineCount, 0)
        guard hiddenCount > 0 else { return }

        switch action {
            case .expandAbove:
                expansion.prefixLineCount += min(gitContextExpansionLineCount, hiddenCount)
            case .expandBelow:
                expansion.suffixLineCount += min(gitContextExpansionLineCount, hiddenCount)
            case .expandAll:
                expansion.prefixLineCount = lineCount
                expansion.suffixLineCount = 0
        }

        compactContextExpansions[blockIndex] = normalizedCompactContextExpansion(expansion, lineCount: lineCount)
        if !refreshRenderedPanesAfterInlineRenderPlanEdit(updateContentWidths: true) {
            render(preservingVerticalPosition: true)
        }
    }

    func normalizedCompactContextExpansion(_ expansion: CompactContextExpansion,
                                                   lineCount: Int) -> CompactContextExpansion {
        var prefixLineCount = min(max(expansion.prefixLineCount, 0), lineCount)
        var suffixLineCount = min(max(expansion.suffixLineCount, 0), max(lineCount - prefixLineCount, 0))
        if prefixLineCount + suffixLineCount >= lineCount {
            prefixLineCount = lineCount
            suffixLineCount = 0
        }
        return CompactContextExpansion(prefixLineCount: prefixLineCount,
                                       suffixLineCount: suffixLineCount)
    }
}
