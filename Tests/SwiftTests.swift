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
            try testMainWindowLoadsAndPicksDiff()
            testDeletionDiffRequiresExplicitPickAndUpdatesMergedPane()
            testChangedRowsKeepStablePaneWidths()
            try testPaneTextIsSelectableAndMergedPaneEditable()
            try testMergedPaneTextBecomesSelectableAfterPick()
            try testSidePickUndoRedoRestoresMergedState()
            try testManualMergedEditEnablesSaveAndShowsManualText()
            try testSameLineManualMergedEditDoesNotRerenderTextView()
            try testManualMergedEditUndoRedoRestoresBlockState()
            try testUndoPreservesCaretInsideChangedBlock()
            try testManualMergedEditNormalizesToRightPick()
            try testManualMergedEditCanBreakLineAtEndOfChangedLine()
            try testAllBlankRowsInDeletionBlockAreEditable()
            try testMergedPaneAcceptsMultiLinePasteText()
            try testMergedEditAllowsEqualRows()
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
        } catch {
            fputs("Swift test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
