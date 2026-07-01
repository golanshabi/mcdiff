#pragma once

#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace macdiff {

using LineNumber = std::uint32_t;
constexpr LineNumber InvalidLineNumber = std::numeric_limits<LineNumber>::max();

enum class DiffBlockKind { Invalid, Equal, Changed };
enum class PickSide { Invalid, Unpicked, Left, Right, Manual };

struct DiffBlock {
    DiffBlockKind kind = DiffBlockKind::Invalid;
    std::vector<std::string> leftLines;
    std::vector<std::string> rightLines;
    std::vector<std::string> manualLines;
    LineNumber leftStartLine = InvalidLineNumber;
    LineNumber rightStartLine = InvalidLineNumber;
    PickSide pick = PickSide::Unpicked;
};

struct DiffDocument {
    std::vector<DiffBlock> blocks;
};

}
