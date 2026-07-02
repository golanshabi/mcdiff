import AppKit

extension MainWindowController {
    @objc func scrollPaneHorizontally(_ sender: PaneHorizontalSlider) {
        applySharedHorizontalValue(sender.doubleValue)
    }

    func paneTextClipView(_ clipView: PaneTextClipView, didScrollHorizontallyBy deltaX: CGFloat) {
        let maxOffset = sharedMaxOffset()
        guard maxOffset > 0 else { return }
        applySharedHorizontalValue(sharedHorizontalValue + Double(deltaX * horizontalWheelSensitivity / maxOffset))
    }

    func configureHorizontalScrollers() {
        horizontalScrollerRow.orientation = .horizontal
        horizontalScrollerRow.spacing = 0
        horizontalScrollerRow.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)

        paneScrollerStack.orientation = .horizontal
        paneScrollerStack.spacing = 0
        paneScrollerStack.distribution = .fill
        paneScrollerStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paneScrollerStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var equalWidthScrollers = [PaneHorizontalSlider]()
        for pane in DiffPane.allCases {
            let scroller = PaneHorizontalSlider(pane: pane)
            scroller.identifier = NSUserInterfaceItemIdentifier("\(pane.identifier)HorizontalScroller")
            scroller.target = self
            scroller.action = #selector(scrollPaneHorizontally(_:))
            scroller.controlSize = .regular
            scroller.isEnabled = false
            scroller.doubleValue = 0
            scroller.heightAnchor.constraint(equalToConstant: horizontalScrollerHeight).isActive = true
            paneScrollers[pane] = scroller
            paneScrollerStack.addArrangedSubview(scroller)
            equalWidthScrollers.append(scroller)
            if pane != .right {
                paneScrollerStack.addArrangedSubview(horizontalScrollerSpacer(width: pickButtonSlotWidth))
            }
        }
        if let firstScroller = equalWidthScrollers.first {
            for scroller in equalWidthScrollers.dropFirst() {
                scroller.widthAnchor.constraint(equalTo: firstScroller.widthAnchor).isActive = true
            }
        }
        horizontalScrollerRow.addArrangedSubview(paneScrollerStack)
    }

    func horizontalScrollerSpacer(width: CGFloat) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    func resetHorizontalOffsets() {
        sharedHorizontalValue = 0
        for state in paneStates.values {
            state.offset = 0
        }
        updateHorizontalScrollers()
    }

    func updatePaneContentWidths() {
        let sharedContentWidth = DiffPane.allCases
            .map(measuredContentWidth(for:))
            .max() ?? 0
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.contentWidth = sharedContentWidth
        }
        applySharedHorizontalValue(sharedHorizontalValue)
    }

    func measuredContentWidth(for pane: DiffPane) -> CGFloat {
        guard let document else { return 0 }
        var maxWidth: CGFloat = 1
        for (blockIndex, block) in document.blocks.enumerated() {
            for line in widthCandidateLines(for: block, blockIndex: blockIndex, pane: pane) {
                maxWidth = max(maxWidth, measuredLineWidth(line))
            }
        }
        return maxWidth
    }

    func widthCandidateLines(for block: MDBlock, blockIndex: Int, pane: DiffPane) -> [String] {
        if rendersConflictContextOnly, block.kind == .equal {
            let lines: [String]
            switch pane {
                case .left:
                    lines = block.leftLines ?? []
                case .right:
                    lines = block.rightLines ?? []
                case .merged:
                    if block.pick == .manual {
                        lines = block.manualLines ?? []
                    } else {
                        lines = block.leftLines ?? []
                    }
            }
            return compactedContextLines(lines, start: nil, blockIndex: blockIndex).lines
        }

        switch pane {
            case .left:
                return block.leftLines ?? []
            case .right:
                return block.rightLines ?? []
            case .merged:
                if block.kind == .equal {
                    if block.pick == .manual {
                        return block.manualLines ?? []
                    }
                    return block.leftLines ?? []
                }

                var lines = [String]()
                lines.append(contentsOf: block.leftLines ?? [])
                lines.append(contentsOf: block.rightLines ?? [])
                lines.append(contentsOf: block.manualLines ?? [])
                return lines
        }
    }

    func measuredLineWidth(_ line: String) -> CGFloat {
        let text = line.isEmpty ? " " : line
        let width = (text as NSString).size(withAttributes: [.font: paneTextFont]).width
        return ceil(width) + 1
    }

    func sharedMaxContentWidth() -> CGFloat {
        paneStates.values.map(\.contentWidth).max() ?? 0
    }

    func refreshPaneViewportWidths() {
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.viewportWidth = paneTextClipViews[pane]?.map(\.bounds.width).max() ?? 0
        }
        applySharedHorizontalValue(sharedHorizontalValue)
    }

    func applySharedHorizontalValue(_ value: Double) {
        sharedHorizontalValue = min(max(value, 0), 1)
        for pane in DiffPane.allCases {
            guard let state = paneStates[pane] else { continue }
            state.offset = CGFloat(sharedHorizontalValue) * state.maxOffset
            state.clampOffset()
            applyHorizontalOffset(for: pane)
        }
        updateHorizontalScrollers()
    }

    func applyHorizontalOffset(for pane: DiffPane) {
        guard let state = paneStates[pane] else { return }
        for clip in paneTextClipViews[pane] ?? [] {
            clip.textOffset = state.offset
        }
    }

    func updateHorizontalScrollers() {
        for pane in DiffPane.allCases {
            updateHorizontalScroller(for: pane)
        }
    }

    func updateHorizontalScroller(for pane: DiffPane) {
        guard let scroller = paneScrollers[pane] else { return }
        scroller.isEnabled = sharedMaxOffset() > 0.5
        scroller.doubleValue = sharedHorizontalValue
    }

    func sharedMaxOffset() -> CGFloat {
        paneStates.values.map(\.maxOffset).max() ?? 0
    }
}
