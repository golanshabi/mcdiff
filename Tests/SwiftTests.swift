import Foundation

@main
private enum SwiftTests {
    static func main() {
        do {
            #if !MCD_LOGGING_DISABLED
            try testLoggerCreatesRunFolderAndPrunesOldRuns()
            #endif
            try testBridgeDiffMergeAndErrors()
            try testBridgeConflictDocumentParsing()
            try testGitBridgeListsAndStagesConflict()
            testMainWindowInitialState()
            try testMainWindowIdenticalFilesEnableSaveWithoutPick()
            try testMainWindowAppliesSyntaxColorsByFileType()
            try testMainWindowLoadsAndPicksDiff()
            try testPickButtonsStartAtTopOfMultiLineDiff()
            testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane()
            try testBlankSourceLinesKeepLineNumbers()
            testChangedRowsKeepStablePaneWidths()
            try testPaneTextIsSelectableAndMergedPaneEditable()
            try testMergedPaneTextBecomesSelectableAfterPick()
            try testSidePickUndoRedoRestoresMergedState()
            try testManualMergedEditEnablesSaveAndShowsManualText()
            try testMergedSyntaxColorsRefreshAfterIdleEdit()
            try testSameLineManualMergedEditDoesNotRerenderTextView()
            try testManualMergedEditUndoRedoRestoresBlockState()
            try testUndoPreservesCaretInsideChangedBlock()
            try testManualMergedEditNormalizesToRightPick()
            try testManualMergedEditCanBreakLineAtEndOfChangedLine()
            try testRepeatedNewlineMergedEditDoesNotRerenderTextView()
            try testWideMergedEditDoesNotRerenderTextView()
            try testRebreakingLineMergedFromChangedAndEqualRowsRestoresBoundary()
            try testAllBlankRowsInDeletionBlockAreEditable()
            try testMergedPaneAcceptsMultiLinePasteText()
            try testMergedEditAllowsEqualRows()
            try testNewlineEditInEqualRowsKeepsCaretVisible()
            try testUndoPreservesCaretInsideEqualRows()
            try testEditingEqualLineAboveConflictDoesNotResolveConflict()
            try testEditingAtEndOfEqualLineAboveConflictDoesNotResolveConflict()
            try testMergedEditCanSpanMultipleBlocks()
            try testCrossBlockMergedEditUndoRestoresEveryAffectedBlock()
            try testDeletingManualMergedTextLeavesResolvedEmptyBlock()
            try testPaneUsesOneNativeSelectionAcrossMultipleTextBlocks()
            try testNativeTextSelectionKeepsPartialWordRange()
            try testPickingOneBlockLeavesOtherMergedBlocksBlankAndUnsaved()
            try testPickingSmallerConflictKeepsLeftAndRightRowsVisible()
            try testLongLineSlidersMoveAllPanesTogetherWithoutChangingPaneWidths()
            try testMainWindowGitMergeToolSaveWritesMergedPath()
            try testMainWindowGitMergeToolCompactsLargeContextAndPreservesSave()
            try testMainWindowGitModeSavesAndStagesSelectedConflict()
            try testGitFileBrowserSidebarToggleHidesSidebarAndResizeHandleChangesWidth()
            try testMainWindowGitModeStagesMarkerlessUnmergedFile()
            try testMainWindowGitFileBrowserSearchFiltersFolders()
            try testMainWindowGitModeShowsOrdinaryModifiedDiff()
            try testMainWindowGitModeCompactsOrdinaryModifiedDiffContext()
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
