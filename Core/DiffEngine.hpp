#pragma once

#include "DiffTypes.hpp"

namespace macdiff {

DiffDocument buildDiff(const std::string& leftText, const std::string& rightText);

}
