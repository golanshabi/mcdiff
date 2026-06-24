import AppKit

private final class PickButton: NSButton {
    weak var block: MDBlock?
    var picksLeft = false
}

private enum DiffPane {
    case left
    case merged
    case right
}

final class MainWindowController: NSViewController {
    private let leftButton = NSButton(title: "Choose Left File", target: nil, action: nil)
    private let rightButton = NSButton(title: "Choose Right File", target: nil, action: nil)
    private let compareButton = NSButton(title: "Compare", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Result", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let stack = NSStackView()

    private var leftURL: URL?
    private var rightURL: URL?
    private var document: MDDocument?

    override func loadView() {
        AppLogger.info("Loading main view.")
        view = NSView()

        let bar = NSStackView(views: [leftButton, rightButton, compareButton, saveButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true

        let root = NSStackView(views: [bar, scroll])
        root.orientation = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)
        ])
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor)
        ])

        leftButton.target = self; leftButton.action = #selector(chooseLeft)
        rightButton.target = self; rightButton.action = #selector(chooseRight)
        compareButton.target = self; compareButton.action = #selector(compare)
        saveButton.target = self; saveButton.action = #selector(save)
        updateButtons()
        AppLogger.info("Main view loaded.")
    }

    func load(left: URL, right: URL) {
        AppLogger.info("Received files to load left=\(left.path) right=\(right.path)")
        leftURL = left
        rightURL = right
        compare()
    }

    @objc private func chooseLeft() {
        leftURL = pickFile()
        AppLogger.info("Left file selected: \(leftURL?.path ?? "none")")
        updateButtons()
    }

    @objc private func chooseRight() {
        rightURL = pickFile()
        AppLogger.info("Right file selected: \(rightURL?.path ?? "none")")
        updateButtons()
    }

    @objc private func compare() {
        guard let leftURL, let rightURL else { return }
        AppLogger.info("Starting compare left=\(leftURL.path) right=\(rightURL.path)")
        do {
            var error: NSError?
            document = MDMakeDiff(try String(contentsOf: leftURL, encoding: .utf8),
                                  try String(contentsOf: rightURL, encoding: .utf8),
                                  &error)
            if let error {
                AppLogger.error("Compare failed from bridge: \(error.localizedDescription)")
                show(error.localizedDescription)
            } else {
                AppLogger.info("Compare succeeded blocks=\(document?.blocks.count ?? 0)")
            }
            render()
        } catch {
            AppLogger.error("Compare failed while reading files: \(error.localizedDescription)")
            show(error.localizedDescription)
        }
        updateButtons()
    }

    @objc private func save() {
        guard let document else { return }
        AppLogger.info("Starting save.")
        do {
            let text = try document.mergedText()
            let panel = NSSavePanel()
            if panel.runModal() == .OK, let url = panel.url {
                try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                AppLogger.info("Saved merged text to \(url.path) bytes=\(text.utf8.count)")
            } else {
                AppLogger.info("Save panel cancelled.")
            }
        } catch {
            AppLogger.error("Save failed: \(error.localizedDescription)")
            show(error.localizedDescription)
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let document else { return }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        var mergedStartLine = 1
        for block in document.blocks {
            stack.addArrangedSubview(blockView(block, mergedStartLine: mergedStartLine))
            mergedStartLine += mergedOutputLineCount(for: block)
        }
    }

    private func blockView(_ block: MDBlock, mergedStartLine: Int) -> NSView {
        let row = NSStackView()
        row.identifier = NSUserInterfaceItemIdentifier("blockRow")
        row.orientation = .horizontal
        row.spacing = 0

        row.addArrangedSubview(pickButtonSlot(block, picksLeft: true))

        let panes = NSStackView()
        panes.orientation = .horizontal
        panes.spacing = 0
        panes.distribution = .fillEqually
        panes.addArrangedSubview(paneView(block, pane: .left, mergedStartLine: mergedStartLine))
        panes.addArrangedSubview(paneView(block, pane: .merged, mergedStartLine: mergedStartLine))
        panes.addArrangedSubview(paneView(block, pane: .right, mergedStartLine: mergedStartLine))
        panes.widthAnchor.constraint(greaterThanOrEqualToConstant: 960).isActive = true
        row.addArrangedSubview(panes)

        row.addArrangedSubview(pickButtonSlot(block, picksLeft: false))
        return row
    }

    private func pickButtonSlot(_ block: MDBlock, picksLeft: Bool) -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: 92).isActive = true

        if block.kind == .changed {
            let button = PickButton(title: picksLeft ? "Use Left" : "Use Right", target: self, action: #selector(pick(_:)))
            button.block = block
            button.picksLeft = picksLeft
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        return view
    }

    private func paneView(_ block: MDBlock, pane: DiffPane, mergedStartLine: Int) -> NSView {
        let view = NSStackView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier(for: pane))
        view.orientation = .vertical
        view.spacing = 6
        view.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        view.wantsLayer = true
        if let color = backgroundColor(for: block, pane: pane) {
            view.layer?.backgroundColor = color.cgColor
        }
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let display = displayedLines(for: block, pane: pane, mergedStartLine: mergedStartLine)
        let content = NSStackView()
        content.orientation = .horizontal
        content.spacing = 8
        content.alignment = .top

        if pane != .merged {
            let numbers = NSTextField(labelWithString: lineNumberText(lines: display.lines, start: display.start))
            numbers.identifier = NSUserInterfaceItemIdentifier("\(identifier(for: pane))LineNumbers")
            numbers.alignment = .right
            numbers.textColor = .secondaryLabelColor
            numbers.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            numbers.lineBreakMode = .byClipping
            numbers.widthAnchor.constraint(equalToConstant: 42).isActive = true
            content.addArrangedSubview(numbers)
        }

        let text = display.lines.joined(separator: "\n")
        let label = NSTextField(labelWithString: text.isEmpty ? " " : text)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
        label.lineBreakMode = NSLineBreakMode.byClipping
        content.addArrangedSubview(label)

        view.addArrangedSubview(content)
        return view
    }

    private func identifier(for pane: DiffPane) -> String {
        switch pane {
            case .left:
                return "leftSide"
            case .merged:
                return "mergedSide"
            case .right:
                return "rightSide"
        }
    }

    private func backgroundColor(for block: MDBlock, pane: DiffPane) -> NSColor? {
        guard block.kind == .changed else { return nil }

        switch pane {
            case .left:
                return block.pick == .left ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemRed.withAlphaComponent(0.16)
            case .merged:
                return block.pick == .unpicked ? NSColor.systemOrange.withAlphaComponent(0.16) : nil
            case .right:
                return block.pick == .right ? NSColor.systemBlue.withAlphaComponent(0.22) : NSColor.systemGreen.withAlphaComponent(0.16)
        }
    }

    private func displayedLines(for block: MDBlock, pane: DiffPane, mergedStartLine: Int) -> (lines: [String], start: Int?) {
        switch pane {
            case .left:
                return (block.leftLines ?? [], block.leftStartLine)
            case .right:
                return (block.rightLines ?? [], block.rightStartLine)
            case .merged:
                return mergedLines(for: block, start: mergedStartLine)
        }
    }

    private func lineNumberText(lines: [String], start: Int?) -> String {
        let lineCount = max(lines.count, 1)
        guard let start, start > 0 else {
            return String(repeating: "\n", count: lineCount - 1)
        }

        return (0..<lineCount).map { index in
            guard index < lines.count, !lines[index].isEmpty else { return "" }
            return "\(start + index)"
        }.joined(separator: "\n")
    }

    private func mergedLines(for block: MDBlock, start: Int) -> (lines: [String], start: Int?) {
        if block.kind == .equal {
            return (block.leftLines ?? [], start)
        }

        switch block.pick {
            case .left:
                return (block.leftLines ?? [], start)
            case .right:
                return (block.rightLines ?? [], start)
            case .unpicked:
                return (["Unresolved"], nil)
            @unknown default:
                return (["Unresolved"], nil)
        }
    }

    private func mergedOutputLineCount(for block: MDBlock) -> Int {
        if block.kind == .equal {
            return block.leftLines?.count ?? 0
        }

        switch block.pick {
            case .left:
                return block.leftLines?.count ?? 0
            case .right:
                return block.rightLines?.count ?? 0
            case .unpicked:
                return 0
            @unknown default:
                return 0
        }
    }

    @objc private func pick(_ sender: PickButton) {
        guard let block = sender.block else { return }
        block.pick = sender.picksLeft ? .left : .right
        AppLogger.info("Picked \(sender.picksLeft ? "left" : "right") for changed block left_start=\(block.leftStartLine) right_start=\(block.rightStartLine)")
        render()
        updateButtons()
    }

    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func updateButtons() {
        compareButton.isEnabled = leftURL != nil && rightURL != nil
        saveButton.isEnabled = document?.canSave() == true
        AppLogger.info("Updated buttons compare_enabled=\(compareButton.isEnabled) save_enabled=\(saveButton.isEnabled)")
    }

    private func show(_ message: String) {
        AppLogger.error("Showing alert: \(message)")
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
