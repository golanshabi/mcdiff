import AppKit

private struct PaneContentWidthMeasurement {
    let width: CGFloat
    let lineCount: Int
    let characterCount: Int
    let maxLineLength: Int
    let collectMilliseconds: Double
    let measureMilliseconds: Double
}

extension MainWindowController {
    @objc func scrollPaneHorizontally(_ sender: PaneHorizontalSlider) {
        applySharedHorizontalValue(sender.doubleValue)
    }

    func paneTextClipView(_ clipView: PaneTextClipView, didScrollHorizontallyBy deltaX: CGFloat) {
        let maxOffset = sharedMaxOffset()
        guard maxOffset > 0 else { return }
        applySharedHorizontalValue(sharedHorizontalValue + Double(deltaX * horizontalWheelSensitivity / maxOffset))
    }

    func paneTextClipView(_ clipView: PaneTextClipView, didRequestHorizontalOffset offset: CGFloat) {
        let maxOffset = sharedMaxOffset()
        guard maxOffset > 0 else { return }
        applySharedHorizontalValue(Double(offset / maxOffset))
    }

    func revealMergedSelectionHorizontally() {
        guard let mergedTextView,
              let clip = paneTextClipViews[.merged]?.first(where: { $0.editableTextView === mergedTextView }) else {
            return
        }
        clip.revealSelectionHorizontallyIfNeeded()
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
                let spacer = horizontalScrollerSpacer(width: pickButtonSlotWidth)
                paneScrollerSpacers[pane] = spacer
                paneScrollerStack.addArrangedSubview(spacer)
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

    func setVisibleHorizontalPanes(_ panes: [DiffPane]) {
        let visiblePanes = Set(panes)
        visibleRenderPanes = panes
        for pane in DiffPane.allCases {
            paneScrollers[pane]?.isHidden = !visiblePanes.contains(pane)
        }

        let showsPickColumnSpacers = panes == DiffPane.allCases
        for spacer in paneScrollerSpacers.values {
            spacer.isHidden = !showsPickColumnSpacers
        }
    }

    func resetHorizontalOffsets() {
        sharedHorizontalValue = 0
        for state in paneStates.values {
            state.offset = 0
        }
        updateHorizontalScrollers()
    }

    func updatePaneContentWidths(for plan: RenderPlan) {
        setVisibleHorizontalPanes(plan.visiblePanes)
        var phases = [TimedPhase]()
        var measurements = [DiffPane: PaneContentWidthMeasurement]()
        for pane in plan.visiblePanes {
            let (measurement, phase) = timed("measure\(pane.identifier)") {
                measuredContentWidthDetails(for: plan.panes[pane] ?? PaneRenderContent())
            }
            phases.append(phase)
            measurements[pane] = measurement
        }
        let sharedContentWidth = measurements.values.map(\.width).max() ?? 0
        phases.append(timed("assignWidths") {
            for pane in DiffPane.allCases {
                guard let state = paneStates[pane] else { continue }
                state.contentWidth = plan.visiblePanes.contains(pane) ? sharedContentWidth : 0
            }
        }.1)
        phases.append(timed("applyOffset") {
            applySharedHorizontalValue(sharedHorizontalValue)
        }.1)

        let total = phases.reduce(0) { $0 + $1.milliseconds }
        if total >= 16 {
            let detailText = plan.visiblePanes.compactMap { pane -> String? in
                guard let measurement = measurements[pane] else { return nil }
                return "\(pane.identifier)Lines=\(measurement.lineCount) \(pane.identifier)Chars=\(measurement.characterCount) \(pane.identifier)MaxLine=\(measurement.maxLineLength) \(pane.identifier)Collect=\(String(format: "%.1f", measurement.collectMilliseconds))ms \(pane.identifier)Measure=\(String(format: "%.1f", measurement.measureMilliseconds))ms \(pane.identifier)Width=\(format(measurement.width))"
            }.joined(separator: " ")
            logPerformance("contentWidths",
                           phases: phases,
                           metadata: "sharedWidth=\(format(sharedContentWidth)) \(detailText)",
                           minimumTotalMilliseconds: 16)
        }
    }

    private func measuredContentWidthDetails(for content: PaneRenderContent) -> PaneContentWidthMeasurement {
        var maxWidth: CGFloat = 1
        var lineCount = 0
        var characterCount = 0
        var maxLineLength = 0
        var measureNanoseconds: UInt64 = 0
        let measureStart = DispatchTime.now().uptimeNanoseconds
        for line in content.textLines {
            let lineLength = (line as NSString).length
            lineCount += 1
            characterCount += lineLength
            maxLineLength = max(maxLineLength, lineLength)
            maxWidth = max(maxWidth, measuredLineWidth(line))
        }
        measureNanoseconds += DispatchTime.now().uptimeNanoseconds - measureStart
        return PaneContentWidthMeasurement(width: maxWidth,
                                           lineCount: lineCount,
                                           characterCount: characterCount,
                                           maxLineLength: maxLineLength,
                                           collectMilliseconds: 0,
                                           measureMilliseconds: Double(measureNanoseconds) / 1_000_000.0)
    }

    func measuredLineWidth(_ line: String) -> CGFloat {
        let text = line.isEmpty ? " " : line
        let width = (text as NSString).size(withAttributes: [.font: paneTextFont]).width
        return ceil(width) + 1
    }

    func sharedMaxContentWidth() -> CGFloat {
        visibleRenderPanes.compactMap { paneStates[$0]?.contentWidth }.max() ?? 0
    }

    func refreshPaneViewportWidths() {
        let start = DispatchTime.now().uptimeNanoseconds
        for pane in visibleRenderPanes {
            guard let state = paneStates[pane] else { continue }
            state.viewportWidth = paneTextClipViews[pane]?.map(\.bounds.width).max() ?? 0
        }
        applySharedHorizontalValue(sharedHorizontalValue)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        if elapsed >= 8 {
            let clipCount = paneTextClipViews.values.reduce(0) { $0 + $1.count }
            logInputPerformance("refreshPaneViewportWidths",
                                milliseconds: elapsed,
                                metadata: "clips=\(clipCount) maxOffset=\(format(sharedMaxOffset()))")
        }
    }

    func applySharedHorizontalValue(_ value: Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        sharedHorizontalValue = min(max(value, 0), 1)
        for pane in visibleRenderPanes {
            guard let state = paneStates[pane] else { continue }
            state.offset = CGFloat(sharedHorizontalValue) * state.maxOffset
            state.clampOffset()
            applyHorizontalOffset(for: pane)
        }
        updateHorizontalScrollers()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        if elapsed >= 8 {
            let clipCount = paneTextClipViews.values.reduce(0) { $0 + $1.count }
            logInputPerformance("applySharedHorizontalValue",
                                milliseconds: elapsed,
                                metadata: "value=\(String(format: "%.3f", sharedHorizontalValue)) clips=\(clipCount) maxOffset=\(format(sharedMaxOffset()))")
        }
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
        guard visibleRenderPanes.contains(pane) else {
            scroller.isEnabled = false
            scroller.doubleValue = 0
            return
        }
        scroller.isEnabled = sharedMaxOffset() > 0.5
        scroller.doubleValue = sharedHorizontalValue
    }

    func sharedMaxOffset() -> CGFloat {
        visibleRenderPanes.compactMap { paneStates[$0]?.maxOffset }.max() ?? 0
    }
}
