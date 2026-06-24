import Foundation
import Darwin

var AppLoggerIsTesting = false
var AppLoggerTestingBaseDirectory: URL?

enum AppLogLevel: String {
    case info = "INFO"
    case error = "ERROR"
}

enum AppLogger {
    static func initialize() {
        _ = logDirectory
    }

    static func info(_ message: String,
                     file: String = #fileID,
                     function: String = #function,
                     line: Int = #line) {
        write(.info, message, file: file, function: function, line: line)
    }

    static func error(_ message: String,
                      file: String = #fileID,
                      function: String = #function,
                      line: Int = #line) {
        write(.error, message, file: file, function: function, line: line)
    }

    private static let logDirectory: URL = {
        let manager = FileManager.default
        let preferredBaseDirectory = AppLoggerTestingBaseDirectory
            ?? manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Logs")
                .appendingPathComponent("mcdiff")

        do {
            return try prepareRunDirectory(in: preferredBaseDirectory)
        } catch {
            let fallbackBaseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mcdiff")
            do {
                return try prepareRunDirectory(in: fallbackBaseDirectory)
            } catch {
                fputs("mcdiff logging failed: \(error.localizedDescription)\n", stderr)
                return fallbackBaseDirectory
            }
        }
    }()

    private static func write(_ level: AppLogLevel, _ message: String, file: String, function: String, line: Int) {
        let manager = FileManager.default

        do {
            let url = logDirectory.appendingPathComponent("swift.log")
            let entry = "\(timestamp()) [\(level.rawValue)] \(URL(fileURLWithPath: file).lastPathComponent):\(function):\(line) - \(message)\n"
            if let data = entry.data(using: .utf8) {
                if manager.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url)
                }
            }
        } catch {
            fputs("mcdiff logging failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func runDirectoryName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd:HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: Date()))_\(getpid())"
    }

    private static func prepareRunDirectory(in baseDirectory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let directory = baseDirectory.appendingPathComponent(runDirectoryName(), isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        try touchLogFile(directory.appendingPathComponent("swift.log"))
        try touchLogFile(directory.appendingPathComponent("cpp.log"))
        if !AppLoggerIsTesting {
            MDSetLogDirectory(directory.path)
        }
        pruneOldRuns(in: baseDirectory)

        return directory
    }

    private static func touchLogFile(_ url: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
    }

    private static func pruneOldRuns(in baseDirectory: URL) {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let runDirectories = contents.compactMap { url -> (url: URL, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]),
                  values.isDirectory == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? values.creationDate ?? Date.distantPast)
        }
        .sorted { $0.date > $1.date }

        for run in runDirectories.dropFirst(10) {
            try? manager.removeItem(at: run.url)
        }
    }
}
