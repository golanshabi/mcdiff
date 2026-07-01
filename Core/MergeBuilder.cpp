#include "MergeBuilder.hpp"
#include "Logger.hpp"

#include <stdexcept>

namespace macdiff {
namespace {

void append(std::string& output, const std::vector<std::string>& lines) {
    for (const auto& line : lines) output += line + "\n";
}

}

bool canMerge(const DiffDocument& doc) {
    for (const auto& block : doc.blocks) {
        if (block.kind == DiffBlockKind::Invalid) {
            MCD_LOG_ERROR("Merge readiness failed: invalid block.");
            return false;
        }
        if (block.kind == DiffBlockKind::Changed &&
            block.pick != PickSide::Left &&
            block.pick != PickSide::Right &&
            block.pick != PickSide::Manual) {
            return false;
        }
    }
    return true;
}

std::string mergeText(const DiffDocument& doc) {
    MCD_LOG_INFO("Merging text blocks=" + std::to_string(doc.blocks.size()));
    std::string output;
    for (const auto& block : doc.blocks) {
        switch (block.kind) {
            case DiffBlockKind::Equal:
                if (block.pick == PickSide::Manual) {
                    append(output, block.manualLines);
                } else {
                    append(output, block.leftLines);
                }
                break;
            case DiffBlockKind::Changed:
                if (block.pick == PickSide::Left) {
                    append(output, block.leftLines);
                } else if (block.pick == PickSide::Right) {
                    append(output, block.rightLines);
                } else if (block.pick == PickSide::Manual) {
                    append(output, block.manualLines);
                } else {
                    // The Objective-C bridge converts this exception into an
                    // NSError so the app can show a recoverable save failure.
                    MCD_LOG_ERROR("Merge failed: changed block has no selected side.");
                    throw std::runtime_error("Choose a side for every changed block.");
                }
                break;
            case DiffBlockKind::Invalid:
                MCD_LOG_ERROR("Merge failed: invalid diff block.");
                throw std::runtime_error("Cannot merge an invalid diff block.");
        }
    }
    MCD_LOG_INFO("Merged text bytes=" + std::to_string(output.size()));
    return output;
}

}
