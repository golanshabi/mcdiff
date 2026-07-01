import AppKit
import Darwin

private let launcherCommandName = "mcdiff"

private enum AppLaunchRequest {
    case empty
    case twoWayCompare(left: URL, right: URL)
    case git(startPath: URL)
    case gitMergeTool(base: URL, local: URL, remote: URL, merged: URL)
    case invalid
}

@main
final class MacDiffApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let controller = MainWindowController()
    private var isMergeToolMode = false
    private var mergeToolCompleted = false

    static func main() {
        let app = NSApplication.shared
        let delegate = MacDiffApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = Array(CommandLine.arguments.dropFirst())
        AppLogger.initialize()
        AppLogger.info("Application launched args_count=\(args.count)")
        let request = parseLaunchRequest(args)
        if case .invalid = request {
            AppLogger.error("Invalid command-line argument count: \(args.count)")
            print("""
            Usage:
              \(launcherCommandName)
              \(launcherCommandName) <left-file> <right-file>
              \(launcherCommandName) --git <path>
              \(launcherCommandName) --merge-tool <base-file> <local-file> <remote-file> <merged-file>
            """)
            
            NSApp.terminate(nil)
            return
        }

        configureMainMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 950),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "mcdiff"
        window.minSize = NSSize(width: 1200, height: 800)
        window.contentViewController = controller
        sizeWindowForCurrentScreen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("Main window created and activated.")

        switch request {
            case .empty:
                break
            case let .twoWayCompare(left, right):
                AppLogger.info("Loading command-line files left=\(left.path) right=\(right.path)")
                controller.load(left: left, right: right)
            case let .git(startPath):
                AppLogger.info("Loading git session start_path=\(startPath.path)")
                controller.loadGit(startPath: startPath)
            case let .gitMergeTool(base, local, remote, merged):
                isMergeToolMode = true
                controller.mergeToolCompletionHandler = { [weak self] success in
                    self?.mergeToolCompleted = success
                    NSApp.terminate(nil)
                }
                AppLogger.info("Loading git mergetool merged_path=\(merged.path)")
                controller.loadGitMergeTool(base: base, local: local, remote: remote, merged: merged)
            case .invalid:
                break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isMergeToolMode else { return }
        exit(mergeToolCompleted ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private func parseLaunchRequest(_ args: [String]) -> AppLaunchRequest {
        if args.isEmpty {
            return .empty
        }

        if args.count == 2, args[0] == "--git" {
            return .git(startPath: URL(fileURLWithPath: args[1]))
        }

        if args.count == 5 && (args[0] == "--merge-tool" || args[0] == "--mergetool") {
            return .gitMergeTool(base: URL(fileURLWithPath: args[1]),
                                 local: URL(fileURLWithPath: args[2]),
                                 remote: URL(fileURLWithPath: args[3]),
                                 merged: URL(fileURLWithPath: args[4]))
        }

        if args.count == 2 {
            return .twoWayCompare(left: URL(fileURLWithPath: args[0]),
                                  right: URL(fileURLWithPath: args[1]))
        }

        return .invalid
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit mcdiff",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo",
                                    action: Selector(("undo:")),
                                    keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo",
                              action: Selector(("redo:")),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",
                                    action: #selector(NSText.cut(_:)),
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",
                                    action: #selector(NSText.copy(_:)),
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",
                                    action: #selector(NSText.paste(_:)),
                                    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Select All",
                                    action: #selector(NSText.selectAll(_:)),
                                    keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func sizeWindowForCurrentScreen() {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        let horizontalInset: CGFloat = 36
        let verticalInset: CGFloat = 36
        let width = max(min(visible.width - horizontalInset * 2, 1800), min(window.minSize.width, visible.width))
        let height = max(min(visible.height - verticalInset * 2, 1100), min(window.minSize.height, visible.height))
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame, display: false)
    }
}
