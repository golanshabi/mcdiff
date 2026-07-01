#import "DiffBridge.h"

#include "../Core/DiffEngine.hpp"
#include "../Core/Logger.hpp"
#include "../Core/MergeBuilder.hpp"

@implementation MDBlock
@end

namespace {

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
        if (error) *error = [NSError errorWithDomain:@"mcdiff" code:2 userInfo:@{NSLocalizedDescriptionKey: @(e.what())}];
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
        MCD_LOG_INFO("Bridge produced document blocks=" + std::to_string(blocks.count));
        return doc;
    } catch (const std::exception& e) {
        MCD_LOG_ERROR(std::string("Bridge diff failed: ") + e.what());
        if (error) *error = [NSError errorWithDomain:@"mcdiff" code:1 userInfo:@{NSLocalizedDescriptionKey: @(e.what())}];
        return nil;
    }
}
