import AppKit
import Foundation

func testLoggerCreatesRunFolderAndPrunesOldRuns() throws {
    let baseDirectory = try temporaryDirectory("logs")
    AppLoggerIsTesting = true
    AppLoggerTestingBaseDirectory = baseDirectory

    let manager = FileManager.default
    for index in 0..<12 {
        let runDirectory = baseDirectory.appendingPathComponent("old-\(index)", isDirectory: true)
        try manager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: TimeInterval(index))
        try manager.setAttributes([.modificationDate: date], ofItemAtPath: runDirectory.path)
    }

    AppLogger.initialize()
    AppLogger.info("swift logger test")

    let runDirectories = try manager.contentsOfDirectory(
        at: baseDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ).filter { url in
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    assertTrue(runDirectories.count == 10, "logger keeps exactly 10 run folders")
    let currentRun = runDirectories.first { $0.lastPathComponent.hasSuffix("_\(getpid())") }
    assertTrue(currentRun != nil, "logger creates a current run folder with PID suffix")
    assertTrue(currentRun!.lastPathComponent.range(
        of: #"^\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2}_\d+$"#,
        options: .regularExpression
    ) != nil, "logger run folder is date-first and PID-last")
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("swift.log").path), "swift.log exists")
    assertTrue(manager.fileExists(atPath: currentRun!.appendingPathComponent("cpp.log").path), "cpp.log exists")

    let swiftLog = try String(contentsOf: currentRun!.appendingPathComponent("swift.log"), encoding: .utf8)
    assertTrue(swiftLog.contains("swift logger test"), "swift.log contains written message")

    testLogDirectory = currentRun
    MDSetLogDirectory(currentRun!.path)
}

func testBridgeDiffMergeAndErrors() throws {
    var error: NSError?
    guard let document = MDMakeDiff("one\nleft\nthree\n",
                                    "one\nright\nthree\n",
                                    &error) else {
        assertTrue(false, "bridge returns document")
        return
    }

    assertTrue(error == nil, "bridge diff has no error")
    assertTrue(document.blocks.count == 3, "bridge document has expected block count")
    assertTrue(document.canSave() == false, "bridge document cannot save before pick")

    do {
        _ = try document.mergedText()
        assertTrue(false, "bridge merge throws before pick")
    } catch {
        assertTrue(error.localizedDescription.contains("Choose a side"), "bridge merge reports pick error")
    }

    let changedBlock = document.blocks[1]
    changedBlock.pick = .right
    assertTrue(document.canSave(), "bridge document can save after pick")

    let merged = try document.mergedText()
    assertTrue(merged == "one\nright\nthree\n", "bridge merge after pick output")

    changedBlock.pick = .manual
    changedBlock.manualLines = ["manual", "merged"]
    assertTrue(document.canSave(), "bridge document can save after manual edit")
    let manualMerged = try document.mergedText()
    assertTrue(manualMerged == "one\nmanual\nmerged\nthree\n", "bridge merge after manual edit output")

    changedBlock.manualLines = []
    let emptyManualMerged = try document.mergedText()
    assertTrue(emptyManualMerged == "one\nthree\n", "bridge merge after empty manual edit output")

    #if !MCD_LOGGING_DISABLED
    guard let testLogDirectory else {
        assertTrue(false, "test log directory is available")
        return
    }
    let cppLog = try String(contentsOf: testLogDirectory.appendingPathComponent("cpp.log"), encoding: .utf8)
    assertTrue(cppLog.contains("Bridge requested diff"), "cpp.log contains bridge diff message")
    assertTrue(cppLog.contains("Merged text bytes"), "cpp.log contains merge message")
    #endif
}

func testBridgeConflictDocumentParsing() throws {
    var error: NSError?
    guard let document = MDMakeConflictDocument("""
    before
    <<<<<<< HEAD
    ours
    ||||||| base
    base
    =======
    theirs
    >>>>>>> branch
    after

    """, &error) else {
        assertTrue(false, "bridge parses conflict document")
        return
    }

    assertTrue(error == nil, "conflict document parse has no error")
    assertTrue(document.blocks.count == 3, "conflict document has expected block count")
    assertTrue(document.blocks[1].kind == .changed, "conflict document creates changed block")
    assertTrue(document.blocks[1].leftLines == ["ours"], "conflict document left side")
    assertTrue(document.blocks[1].rightLines == ["theirs"], "conflict document right side ignores diff3 base")
    assertTrue(document.canSave() == false, "conflict document requires resolution")

    document.blocks[1].pick = .manual
    document.blocks[1].manualLines = ["resolved"]
    let merged = try document.mergedText()
    assertTrue(merged == "before\nresolved\nafter\n", "conflict document merged output removes markers")
}

func testGitBridgeListsAndStagesConflict() throws {
    let repo = try makeConflictedRepository("git-bridge-conflict")
    let nested = repo.appendingPathComponent("subdir", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    var error: NSError?
    guard let rootPath = MDGitDiscoverRepository(nested.path, &error) else {
        assertTrue(false, "git repository is discovered")
        return
    }
    assertTrue(URL(fileURLWithPath: rootPath).standardizedFileURL.path == repo.standardizedFileURL.path,
               "git discovery returns repo root")

    guard let conflictFiles = MDGitConflictFiles(rootPath, &error) else {
        assertTrue(false, "git conflicts are listed")
        return
    }
    assertTrue(conflictFiles.contains { ($0.relativePath ?? "") == "conflict.txt" },
               "git conflict list includes conflicted path")

    let conflictFile = repo.appendingPathComponent("conflict.txt")
    var text = try String(contentsOf: conflictFile, encoding: .utf8)
    assertTrue(text.contains("<<<<<<<"), "test repo has conflict markers before resolution")
    try "resolved\n".write(to: conflictFile, atomically: true, encoding: .utf8)

    var stageError: NSError?
    assertTrue(MDGitStageFile(rootPath, "conflict.txt", &stageError), "resolved conflict stages successfully")
    assertTrue(stageError == nil, "staging has no error")
    text = try String(contentsOf: conflictFile, encoding: .utf8)
    assertTrue(!text.contains("<<<<<<<"), "resolved worktree file has no conflict markers")
    let unmerged = try runGit(["ls-files", "-u"], in: repo)
    assertTrue(unmerged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "staging resolved file clears unmerged index entries")
}
