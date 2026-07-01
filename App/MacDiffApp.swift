import AppKit

private let launcherCommandName = "mcdiff"

@main
final class MacDiffApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let controller = MainWindowController()

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
        if args.count != 0 && args.count != 2 {
            AppLogger.error("Invalid command-line argument count: \(args.count)")
            print("""
            Usage:
              \(launcherCommandName) <left-file> <right-file>
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

        if args.count == 2 {
            AppLogger.info("Loading command-line files left=\(args[0]) right=\(args[1])")
            controller.load(left: URL(fileURLWithPath: args[0]), right: URL(fileURLWithPath: args[1]))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
