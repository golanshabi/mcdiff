#import "DiffBridge.h"

#include "../Core/ConflictParser.hpp"
#include "../Core/DiffEngine.hpp"
#include "../Core/Logger.hpp"
#include "../Core/MergeBuilder.hpp"

#include <git2.h>

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

NSError *lastGitError(NSInteger code, const char *fallback) {
    const git_error *error = git_error_last();
    return errorWithMessage(code, error && error->message ? error->message : fallback);
}

struct Libgit2BridgeRuntime {
    Libgit2BridgeRuntime() {
        if (git_libgit2_init() < 0) {
            throw std::runtime_error("Failed to initialize libgit2.");
        }
        MCD_LOG_INFO("Initialized bridge libgit2 runtime.");
    }

    ~Libgit2BridgeRuntime() {
        git_libgit2_shutdown();
        MCD_LOG_INFO("Shut down bridge libgit2 runtime.");
    }
};

void ensureBridgeLibgit2Runtime() {
    static Libgit2BridgeRuntime runtime;
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

std::string conflictPath(const git_index_entry *ancestor,
                         const git_index_entry *ours,
                         const git_index_entry *theirs) {
    if (ours && ours->path) return ours->path;
    if (theirs && theirs->path) return theirs->path;
    if (ancestor && ancestor->path) return ancestor->path;
    return "";
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
        ensureBridgeLibgit2Runtime();
        git_repository *repo = nullptr;
        const int result = git_repository_open_ext(&repo, startPath.fileSystemRepresentation, 0, nullptr);
        if (result != 0) {
            if (error) *error = lastGitError(4, "No git repository found.");
            return nil;
        }

        const char *workdir = git_repository_workdir(repo);
        if (!workdir) {
            git_repository_free(repo);
            if (error) *error = errorWithMessage(4, "Bare git repositories are not supported.");
            return nil;
        }

        NSString *path = @(workdir);
        git_repository_free(repo);
        MCD_LOG_INFO("Discovered git repository root=" + std::string(path.UTF8String ?: ""));
        return path;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git discovery failed: ") + e.what());
        if (error) *error = errorWithMessage(4, e.what());
        return nil;
    }
}

extern "C" NSArray<MDGitConflictFile *> *MDGitConflictFiles(NSString *repositoryRoot, NSError **error) {
    try {
        ensureBridgeLibgit2Runtime();
        git_repository *repo = nullptr;
        if (git_repository_open(&repo, repositoryRoot.fileSystemRepresentation) != 0) {
            if (error) *error = lastGitError(5, "Could not open git repository.");
            return nil;
        }

        git_index *index = nullptr;
        if (git_repository_index(&index, repo) != 0) {
            git_repository_free(repo);
            if (error) *error = lastGitError(5, "Could not read git index.");
            return nil;
        }

        git_index_conflict_iterator *iterator = nullptr;
        int iteratorResult = git_index_conflict_iterator_new(&iterator, index);
        if (iteratorResult != 0) {
            git_index_free(index);
            git_repository_free(repo);
            if (iteratorResult == GIT_ENOTFOUND) return @[];
            if (error) *error = lastGitError(5, "Could not inspect git conflicts.");
            return nil;
        }

        NSMutableArray<MDGitConflictFile *> *files = [NSMutableArray array];
        const git_index_entry *ancestor = nullptr;
        const git_index_entry *ours = nullptr;
        const git_index_entry *theirs = nullptr;
        while (git_index_conflict_next(&ancestor, &ours, &theirs, iterator) == 0) {
            const std::string path = conflictPath(ancestor, ours, theirs);
            if (path.empty()) continue;

            MDGitConflictFile *file = [MDGitConflictFile new];
            file.relativePath = @(path.c_str());
            file.isTextConflict = YES;
            file.message = @"";
            [files addObject:file];
        }

        git_index_conflict_iterator_free(iterator);
        git_index_free(index);
        git_repository_free(repo);

        NSArray<MDGitConflictFile *> *sorted = [files sortedArrayUsingDescriptors:@[
            [NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:YES]
        ]];
        MCD_LOG_INFO("Listed git conflict files count=" + std::to_string(sorted.count));
        return sorted;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git conflict listing failed: ") + e.what());
        if (error) *error = errorWithMessage(5, e.what());
        return nil;
    }
}

extern "C" BOOL MDGitStageFile(NSString *repositoryRoot, NSString *relativePath, NSError **error) {
    try {
        ensureBridgeLibgit2Runtime();
        git_repository *repo = nullptr;
        if (git_repository_open(&repo, repositoryRoot.fileSystemRepresentation) != 0) {
            if (error) *error = lastGitError(6, "Could not open git repository.");
            return NO;
        }

        git_index *index = nullptr;
        if (git_repository_index(&index, repo) != 0) {
            git_repository_free(repo);
            if (error) *error = lastGitError(6, "Could not read git index.");
            return NO;
        }

        if (git_index_add_bypath(index, relativePath.UTF8String ?: "") != 0 ||
            git_index_write(index) != 0) {
            git_index_free(index);
            git_repository_free(repo);
            if (error) *error = lastGitError(6, "Could not stage resolved file.");
            return NO;
        }

        git_index_free(index);
        git_repository_free(repo);
        MCD_LOG_INFO("Staged git file relative_path=" + std::string(relativePath.UTF8String ?: ""));
        return YES;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge git staging failed: ") + e.what());
        if (error) *error = errorWithMessage(6, e.what());
        return NO;
    }
}
