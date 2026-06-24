#include "../Core/DiffEngine.hpp"
#include "../Core/MergeBuilder.hpp"

#include <cassert>
#include <stdexcept>
#include <string>

namespace {

using macdiff::DiffBlockKind;
using macdiff::PickSide;

void assertEqualDocument() {
    const auto doc = macdiff::buildDiff("alpha\nbeta\n", "alpha\nbeta\n");

    assert(doc.blocks.size() == 1);
    assert(doc.blocks[0].kind == DiffBlockKind::Equal);
    assert(doc.blocks[0].leftStartLine == 1);
    assert(doc.blocks[0].rightStartLine == 1);
    assert(doc.blocks[0].leftLines.size() == 2);
    assert(doc.blocks[0].rightLines.size() == 2);
    assert(doc.blocks[0].leftLines[0] == "alpha");
    assert(doc.blocks[0].rightLines[1] == "beta");
    assert(macdiff::mergeText(doc) == "alpha\nbeta\n");
}

void assertChangedDocumentAndMerge() {
    auto doc = macdiff::buildDiff("alpha\nleft\nomega\n", "alpha\nright\nomega\n");

    assert(doc.blocks.size() == 3);
    assert(doc.blocks[0].kind == DiffBlockKind::Equal);
    assert(doc.blocks[1].kind == DiffBlockKind::Changed);
    assert(doc.blocks[2].kind == DiffBlockKind::Equal);
    assert(doc.blocks[1].leftStartLine == 2);
    assert(doc.blocks[1].rightStartLine == 2);
    assert(doc.blocks[1].leftLines.size() == 1);
    assert(doc.blocks[1].rightLines.size() == 1);
    assert(doc.blocks[1].leftLines[0] == "left");
    assert(doc.blocks[1].rightLines[0] == "right");
    assert(!macdiff::canMerge(doc));

    bool threw = false;
    try {
        (void)macdiff::mergeText(doc);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    assert(threw);

    doc.blocks[1].pick = PickSide::Right;
    assert(macdiff::canMerge(doc));
    assert(macdiff::mergeText(doc) == "alpha\nright\nomega\n");
}

void assertInsertionAndDeletion() {
    auto inserted = macdiff::buildDiff("alpha\nomega\n", "alpha\nmiddle\nomega\n");
    assert(inserted.blocks.size() == 3);
    assert(inserted.blocks[1].kind == DiffBlockKind::Changed);
    assert(inserted.blocks[1].leftLines.empty());
    assert(inserted.blocks[1].rightLines.size() == 1);
    assert(inserted.blocks[1].rightLines[0] == "middle");

    auto deleted = macdiff::buildDiff("alpha\nmiddle\nomega\n", "alpha\nomega\n");
    assert(deleted.blocks.size() == 3);
    assert(deleted.blocks[1].kind == DiffBlockKind::Changed);
    assert(deleted.blocks[1].leftLines.size() == 1);
    assert(deleted.blocks[1].rightLines.empty());
    assert(deleted.blocks[1].leftLines[0] == "middle");
}

}

int main() {
    assertEqualDocument();
    assertChangedDocumentAndMerge();
    assertInsertionAndDeletion();
    return 0;
}
