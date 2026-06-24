import AppKit

private final class PickButton: NSButton {
    weak var block: MDBlock?
    var picksLeft = false
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
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
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
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let document else { return }
        // Blocks are rendered from the mutable bridge objects, so choosing a
        // side can update the model and redraw without rebuilding the diff.
        for block in document.blocks { stack.addArrangedSubview(blockView(block)) }
    }

    private func blockView(_ block: MDBlock) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0

        row.addArrangedSubview(sideView(block, left: true))
        row.addArrangedSubview(sideView(block, left: false))
        return row
    }

    private func sideView(_ block: MDBlock, left: Bool) -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 6
        view.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.wantsLayer = true
        if block.kind == .changed {
            if (left && block.pick == .left) || (!left && block.pick == .right) {
                view.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.22).cgColor
            } else {
                view.layer?.backgroundColor = (left ? NSColor.systemRed : NSColor.systemGreen)
                    .withAlphaComponent(0.16)
                    .cgColor
            }
        }
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true

        if block.kind == .changed {
            let button = PickButton(title: left ? "Use Left" : "Use Right", target: self, action: #selector(pick(_:)))
            button.block = block
            button.picksLeft = left
            view.addArrangedSubview(button)
        }

        let lines = (left ? block.leftLines : block.rightLines) ?? []
        let start = left ? block.leftStartLine : block.rightStartLine
        let text = lines.enumerated().map { "\(start + $0.offset)  \($0.element)" }.joined(separator: "\n")
        let label = NSTextField(labelWithString: text.isEmpty ? " " : text)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
        label.lineBreakMode = NSLineBreakMode.byClipping
        view.addArrangedSubview(label)
        return view
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
