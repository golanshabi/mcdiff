#pragma once

#include "DiffTypes.hpp"

namespace macdiff {

bool canMerge(const DiffDocument& doc);
std::string mergeText(const DiffDocument& doc);

}
