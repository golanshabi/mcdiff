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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "mcdiff"
        window.center()
        window.contentViewController = controller
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
}
