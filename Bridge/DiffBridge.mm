#import "DiffBridge.h"

#include "../Core/ConflictParser.hpp"
#include "../Core/DiffEngine.hpp"
#include "../Core/GitRepository.hpp"
#include "../Core/Logger.hpp"
#include "../Core/MergeBuilder.hpp"

#include <stdexcept>
#include <string>

@implementation MDGitConflictFile
@end

@implementation MDBlock
@end

namespace {

constexpr const char* ErrorDomain = "mcdiff";

NSError *errorWithMessage(NSInteger code, const char *message) {
    return [NSError errorWithDomain:@(ErrorDomain)
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: @(message ? message : "Unknown error.")}];
}

NSError *errorWithMessage(NSInteger code, const std::string& message) {
    return errorWithMessage(code, message.c_str());
}

macdiff::PickSide corePickSide(MDPickSide pick) {
    switch (pick) {
        case MDPickSideLeft:
            return macdiff::PickSide::Left;
        case MDPickSideRight:
            return macdiff::PickSide::Right;
        case MDPickSideManual:
            return macdiff::PickSide::Manual;
        case MDPickSideUnpicked:
        default:
            return macdiff::PickSide::Unpicked;
    }
}

MDDocument *documentFromCore(const macdiff::DiffDocument& core) {
    NSMutableArray<MDBlock *> *blocks = [NSMutableArray array];

    for (const auto& block : core.blocks) {
        // Convert every core block into an NSObject so Swift/AppKit can own,
        // mutate, and bind the user's left/right merge choice.
        MDBlock *item = [MDBlock new];
        item.kind = block.kind == macdiff::DiffBlockKind::Equal ? MDBlockKindEqual : MDBlockKindChanged;
        item.leftStartLine = static_cast<NSInteger>(block.leftStartLine);
        item.rightStartLine = static_cast<NSInteger>(block.rightStartLine);
        item.pick = MDPickSideUnpicked;
        item.manualLines = @[];

        NSMutableArray<NSString *> *left = [NSMutableArray array];
        NSMutableArray<NSString *> *right = [NSMutableArray array];
        for (const auto& line : block.leftLines) [left addObject:@(line.c_str())];
        for (const auto& line : block.rightLines) [right addObject:@(line.c_str())];
        item.leftLines = left;
        item.rightLines = right;
        [blocks addObject:item];
    }

    MDDocument *doc = [MDDocument new];
    doc.blocks = blocks;
    return doc;
}

MDGitConflictFile *gitFileFromCore(const macdiff::GitFile& core) {
    MDGitConflictFile *file = [MDGitConflictFile new];
    file.relativePath = @(core.relativePath.c_str());
    file.headRelativePath = @(core.headRelativePath.c_str());
    file.isTextConflict = core.isTextConflict;
    file.isConflict = core.isConflict;
    file.message = @(core.message.c_str());
    file.statusDescription = @(core.statusDescription.c_str());
    return file;
}

NSArray<MDGitConflictFile *> *gitFilesFromCore(const std::vector<macdiff::GitFile>& coreFiles) {
    NSMutableArray<MDGitConflictFile *> *files = [NSMutableArray array];
    for (const auto& file : coreFiles) {
        [files addObject:gitFileFromCore(file)];
    }
    return files;
}

}

@implementation MDDocument

- (BOOL)canSave {
    for (MDBlock *block in self.blocks) {
        if (block.kind == MDBlockKindChanged && block.pick == MDPickSideUnpicked) return NO;
    }
    return YES;
}

- (NSString *)mergedText:(NSError **)error {
    MCD_LOG_INFO("Bridge requested merged text blocks=" + std::to_string(self.blocks.count));
    macdiff::DiffDocument doc;
    for (MDBlock *block in self.blocks) {
        macdiff::DiffBlock core;
        // Swift sees Objective-C containers, while the merge engine works with
        // value-type C++ blocks. Keep this translation narrow at the boundary.
        core.kind = block.kind == MDBlockKindEqual ? macdiff::DiffBlockKind::Equal : macdiff::DiffBlockKind::Changed;
        core.leftStartLine = static_cast<macdiff::LineNumber>(block.leftStartLine);
        core.rightStartLine = static_cast<macdiff::LineNumber>(block.rightStartLine);
        core.pick = corePickSide(block.pick);
        for (NSString *line in block.leftLines) core.leftLines.push_back(line.UTF8String ?: "");
        for (NSString *line in block.rightLines) core.rightLines.push_back(line.UTF8String ?: "");
        for (NSString *line in block.manualLines) core.manualLines.push_back(line.UTF8String ?: "");
        doc.blocks.push_back(core);
    }

    try {
        std::string merged = macdiff::mergeText(doc);
        MCD_LOG_INFO("Bridge produced merged text bytes=" + std::to_string(merged.size()));
        return [[NSString alloc] initWithBytes:merged.data() length:merged.size() encoding:NSUTF8StringEncoding];
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge merge failed: ") + e.what());
        if (error) *error = errorWithMessage(2, e.what());
        return nil;
    }
}

@end

extern "C" void MDSetLogDirectory(NSString *directoryPath) {
    macdiff::setLogDirectory(directoryPath.UTF8String ?: "");
}

extern "C" MDDocument *MDMakeDiff(NSString *leftText, NSString *rightText, NSError **error) {
    try {
        MCD_LOG_INFO("Bridge requested diff left_chars=" + std::to_string(leftText.length) +
                     " right_chars=" + std::to_string(rightText.length));
        auto core = macdiff::buildDiff(leftText.UTF8String ?: "", rightText.UTF8String ?: "");
        MDDocument *doc = documentFromCore(core);
        MCD_LOG_INFO("Bridge produced document blocks=" + std::to_string(doc.blocks.count));
        return doc;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge diff failed: ") + e.what());
        if (error) *error = errorWithMessage(1, e.what());
        return nil;
    }
}

extern "C" MDDocument *MDMakeConflictDocument(NSString *worktreeText, NSError **error) {
    try {
        auto core = macdiff::buildConflictDocument(worktreeText.UTF8String ?: "");
        MDDocument *doc = documentFromCore(core);
        return doc;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge conflict parse failed: ") + e.what());
        if (error) *error = errorWithMessage(3, e.what());
        return nil;
    }
}

extern "C" NSString *MDGitDiscoverRepository(NSString *startPath, NSError **error) {
    try {
        std::string path = macdiff::discoverGitRepository(startPath.fileSystemRepresentation);
        return @(path.c_str());
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git discovery failed: ") + e.what());
        if (error) *error = errorWithMessage(4, e.what());
        return nil;
    }
}

extern "C" NSArray<MDGitConflictFile *> *MDGitConflictFiles(NSString *repositoryRoot, NSError **error) {
    try {
        return gitFilesFromCore(macdiff::gitConflictFiles(repositoryRoot.fileSystemRepresentation));
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git conflict listing failed: ") + e.what());
        if (error) *error = errorWithMessage(5, e.what());
        return nil;
    }
}

extern "C" NSArray<MDGitConflictFile *> *MDGitChangedFiles(NSString *repositoryRoot, NSError **error) {
    try {
        return gitFilesFromCore(macdiff::gitChangedFiles(repositoryRoot.fileSystemRepresentation));
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git change listing failed: ") + e.what());
        if (error) *error = errorWithMessage(5, e.what());
        return nil;
    }
}

extern "C" NSString *MDGitHeadFileText(NSString *repositoryRoot, NSString *relativePath, NSError **error) {
    try {
        std::string text = macdiff::gitHeadFileText(repositoryRoot.fileSystemRepresentation,
                                                    relativePath.UTF8String ?: "");
        NSString *string = [[NSString alloc] initWithBytes:text.data()
                                                    length:text.size()
                                                encoding:NSUTF8StringEncoding];
        if (!string && !text.empty()) {
            if (error) *error = errorWithMessage(7, "Could not read HEAD version as UTF-8 text. Binary files are not supported yet.");
            return nil;
        }
        return string ?: @"";
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git HEAD text failed: ") + e.what());
        if (error) *error = errorWithMessage(7, e.what());
        return nil;
    }
}

extern "C" BOOL MDGitStageFile(NSString *repositoryRoot, NSString *relativePath, NSError **error) {
    try {
        macdiff::gitStageFile(repositoryRoot.fileSystemRepresentation,
                              relativePath.UTF8String ?: "");
        return YES;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git staging failed: ") + e.what());
        if (error) *error = errorWithMessage(6, e.what());
        return NO;
    }
}
