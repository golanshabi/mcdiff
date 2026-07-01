#include "../Core/ConflictParser.hpp"
#include "../Core/DiffEngine.hpp"
#include "../Core/MergeBuilder.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

using macdiff::DiffBlock;
using macdiff::DiffBlockKind;
using macdiff::DiffDocument;
using macdiff::InvalidLineNumber;
using macdiff::PickSide;

int failures = 0;

void fail(const std::string& message) {
    std::cerr << "Core test failed: " << message << '\n';
    ++failures;
}

void expect(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

template <typename Exception, typename Fn>
void expectThrows(Fn fn, const std::string& message) {
    try {
        fn();
        fail(message + " did not throw");
    } catch (const Exception&) {
    } catch (...) {
        fail(message + " threw the wrong exception type");
    }
}

void expectLine(const std::vector<std::string>& lines,
                std::size_t index,
                const std::string& expected,
                const std::string& message) {
    expect(lines.size() > index, message + " has enough lines");
    if (lines.size() > index) {
        expect(lines[index] == expected, message + " expected '" + expected + "' got '" + lines[index] + "'");
    }
}

DiffBlock changedBlock(std::vector<std::string> left,
                       std::vector<std::string> right,
                       PickSide pick = PickSide::Unpicked) {
    DiffBlock block;
    block.kind = DiffBlockKind::Changed;
    block.leftLines = std::move(left);
    block.rightLines = std::move(right);
    block.leftStartLine = 1;
    block.rightStartLine = 1;
    block.pick = pick;
    return block;
}

void testEqualDocument() {
    const auto doc = macdiff::buildDiff("alpha\nbeta\n", "alpha\nbeta\n");

    expect(doc.blocks.size() == 1, "equal document has one block");
    expect(doc.blocks[0].kind == DiffBlockKind::Equal, "equal document block kind");
    expect(doc.blocks[0].leftStartLine == 1, "equal document left start");
    expect(doc.blocks[0].rightStartLine == 1, "equal document right start");
    expect(doc.blocks[0].leftLines.size() == 2, "equal document left line count");
    expect(doc.blocks[0].rightLines.size() == 2, "equal document right line count");
    expectLine(doc.blocks[0].leftLines, 0, "alpha", "equal document left first line");
    expectLine(doc.blocks[0].rightLines, 1, "beta", "equal document right second line");
    expect(macdiff::canMerge(doc), "equal document can merge");
    expect(macdiff::mergeText(doc) == "alpha\nbeta\n", "equal document merge output");
}

void testEmptyDocuments() {
    const auto doc = macdiff::buildDiff("", "");

    expect(doc.blocks.empty(), "empty documents produce no blocks");
    expect(macdiff::canMerge(doc), "empty documents can merge");
    expect(macdiff::mergeText(doc).empty(), "empty document merge output");
}

void testReplacementAndMergeChoices() {
    auto doc = macdiff::buildDiff("alpha\nleft\nomega\n", "alpha\nright\nomega\n");

    expect(doc.blocks.size() == 3, "replacement document has three blocks");
    expect(doc.blocks[0].kind == DiffBlockKind::Equal, "replacement first block equal");
    expect(doc.blocks[1].kind == DiffBlockKind::Changed, "replacement middle block changed");
    expect(doc.blocks[2].kind == DiffBlockKind::Equal, "replacement last block equal");
    expect(doc.blocks[1].leftStartLine == 2, "replacement left start");
    expect(doc.blocks[1].rightStartLine == 2, "replacement right start");
    expectLine(doc.blocks[1].leftLines, 0, "left", "replacement left line");
    expectLine(doc.blocks[1].rightLines, 0, "right", "replacement right line");
    expect(!macdiff::canMerge(doc), "replacement cannot merge before pick");
    expectThrows<std::runtime_error>([&] { (void)macdiff::mergeText(doc); }, "replacement merge before pick");

    doc.blocks[1].pick = PickSide::Left;
    expect(macdiff::canMerge(doc), "replacement can merge after left pick");
    expect(macdiff::mergeText(doc) == "alpha\nleft\nomega\n", "replacement left merge output");

    doc.blocks[1].pick = PickSide::Right;
    expect(macdiff::canMerge(doc), "replacement can merge after right pick");
    expect(macdiff::mergeText(doc) == "alpha\nright\nomega\n", "replacement right merge output");
}

void testInsertionAtBeginningMiddleAndEnd() {
    auto beginning = macdiff::buildDiff("beta\n", "alpha\nbeta\n");
    expect(beginning.blocks.size() == 2, "beginning insertion block count");
    expect(beginning.blocks[0].kind == DiffBlockKind::Changed, "beginning insertion first block changed");
    expect(beginning.blocks[0].leftLines.empty(), "beginning insertion has no left lines");
    expectLine(beginning.blocks[0].rightLines, 0, "alpha", "beginning insertion right line");
    beginning.blocks[0].pick = PickSide::Right;
    expect(macdiff::mergeText(beginning) == "alpha\nbeta\n", "beginning insertion merge output");

    auto middle = macdiff::buildDiff("alpha\nomega\n", "alpha\nmiddle\nomega\n");
    expect(middle.blocks.size() == 3, "middle insertion block count");
    expect(middle.blocks[1].kind == DiffBlockKind::Changed, "middle insertion changed block");
    expect(middle.blocks[1].leftLines.empty(), "middle insertion has no left lines");
    expectLine(middle.blocks[1].rightLines, 0, "middle", "middle insertion right line");
    middle.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(middle) == "alpha\nmiddle\nomega\n", "middle insertion merge output");
    middle.blocks[1].pick = PickSide::Left;
    expect(macdiff::mergeText(middle) == "alpha\nomega\n", "middle insertion left-pick merge output");

    auto end = macdiff::buildDiff("alpha\n", "alpha\nomega\n");
    expect(end.blocks.size() == 2, "end insertion block count");
    expect(end.blocks[1].kind == DiffBlockKind::Changed, "end insertion changed block");
    expect(end.blocks[1].leftLines.empty(), "end insertion has no left lines");
    expectLine(end.blocks[1].rightLines, 0, "omega", "end insertion right line");
    end.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(end) == "alpha\nomega\n", "end insertion merge output");
}

void testDeletionAtBeginningMiddleAndEnd() {
    auto beginning = macdiff::buildDiff("alpha\nbeta\n", "beta\n");
    expect(beginning.blocks.size() == 2, "beginning deletion block count");
    expect(beginning.blocks[0].kind == DiffBlockKind::Changed, "beginning deletion first block changed");
    expectLine(beginning.blocks[0].leftLines, 0, "alpha", "beginning deletion left line");
    expect(beginning.blocks[0].rightLines.empty(), "beginning deletion has no right lines");
    beginning.blocks[0].pick = PickSide::Right;
    expect(macdiff::mergeText(beginning) == "beta\n", "beginning deletion merge output");

    auto middle = macdiff::buildDiff("alpha\nmiddle\nomega\n", "alpha\nomega\n");
    expect(middle.blocks.size() == 3, "middle deletion block count");
    expect(middle.blocks[1].kind == DiffBlockKind::Changed, "middle deletion changed block");
    expectLine(middle.blocks[1].leftLines, 0, "middle", "middle deletion left line");
    expect(middle.blocks[1].rightLines.empty(), "middle deletion has no right lines");
    middle.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(middle) == "alpha\nomega\n", "middle deletion merge output");
    middle.blocks[1].pick = PickSide::Left;
    expect(macdiff::mergeText(middle) == "alpha\nmiddle\nomega\n", "middle deletion left-pick merge output");

    auto end = macdiff::buildDiff("a\nb\nc\nd\n", "a\nb\nc\n");
    expect(end.blocks.size() == 2, "end deletion block count");
    expect(end.blocks[1].kind == DiffBlockKind::Changed, "end deletion changed block");
    expectLine(end.blocks[1].leftLines, 0, "d", "end deletion left line");
    expect(end.blocks[1].rightLines.empty(), "end deletion has no right lines");
    end.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(end) == "a\nb\nc\n", "end deletion merge output");
}

void testMultilineReplacementAndBlankLines() {
    auto multiline = macdiff::buildDiff("top\nleft1\nleft2\nbottom\n",
                                        "top\nright1\nright2\nbottom\n");
    expect(multiline.blocks.size() == 3, "multiline replacement block count");
    expect(multiline.blocks[1].kind == DiffBlockKind::Changed, "multiline replacement changed block");
    expect(multiline.blocks[1].leftLines.size() == 2, "multiline replacement left line count");
    expect(multiline.blocks[1].rightLines.size() == 2, "multiline replacement right line count");
    expectLine(multiline.blocks[1].leftLines, 0, "left1", "multiline replacement first left");
    expectLine(multiline.blocks[1].leftLines, 1, "left2", "multiline replacement second left");
    expectLine(multiline.blocks[1].rightLines, 0, "right1", "multiline replacement first right");
    expectLine(multiline.blocks[1].rightLines, 1, "right2", "multiline replacement second right");
    multiline.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(multiline) == "top\nright1\nright2\nbottom\n", "multiline replacement merge output");

    auto blankLine = macdiff::buildDiff("a\n\nc\n", "a\nb\nc\n");
    expect(blankLine.blocks.size() == 3, "blank line replacement block count");
    expect(blankLine.blocks[1].kind == DiffBlockKind::Changed, "blank line replacement changed block");
    expectLine(blankLine.blocks[1].leftLines, 0, "", "blank line replacement left blank line");
    expectLine(blankLine.blocks[1].rightLines, 0, "b", "blank line replacement right line");
    blankLine.blocks[1].pick = PickSide::Left;
    expect(macdiff::mergeText(blankLine) == "a\n\nc\n", "blank line replacement left merge output");
    blankLine.blocks[1].pick = PickSide::Right;
    expect(macdiff::mergeText(blankLine) == "a\nb\nc\n", "blank line replacement right merge output");
}

void testMultipleIndependentHunks() {
    auto doc = macdiff::buildDiff("a\nleft1\nb\nleft2\nc\n", "a\nright1\nb\nright2\nc\n");

    expect(doc.blocks.size() == 5, "multiple hunks block count");
    expect(doc.blocks[1].kind == DiffBlockKind::Changed, "multiple hunks first change");
    expect(doc.blocks[3].kind == DiffBlockKind::Changed, "multiple hunks second change");
    expectLine(doc.blocks[1].leftLines, 0, "left1", "multiple hunks first left");
    expectLine(doc.blocks[1].rightLines, 0, "right1", "multiple hunks first right");
    expectLine(doc.blocks[3].leftLines, 0, "left2", "multiple hunks second left");
    expectLine(doc.blocks[3].rightLines, 0, "right2", "multiple hunks second right");
    expect(!macdiff::canMerge(doc), "multiple hunks cannot merge before picks");

    doc.blocks[1].pick = PickSide::Right;
    expect(!macdiff::canMerge(doc), "multiple hunks cannot merge with partial picks");
    doc.blocks[3].pick = PickSide::Left;
    expect(macdiff::canMerge(doc), "multiple hunks can merge after all picks");
    expect(macdiff::mergeText(doc) == "a\nright1\nb\nleft2\nc\n", "multiple hunks mixed merge output");
}

void testConflictDocumentParsing() {
    auto doc = macdiff::buildConflictDocument(
        "before\n"
        "<<<<<<< HEAD\n"
        "ours\n"
        "=======\n"
        "theirs\n"
        ">>>>>>> branch\n"
        "after\n");

    expect(doc.blocks.size() == 3, "conflict document block count");
    expect(doc.blocks[0].kind == DiffBlockKind::Equal, "conflict document first block equal");
    expect(doc.blocks[1].kind == DiffBlockKind::Changed, "conflict document middle block changed");
    expect(doc.blocks[2].kind == DiffBlockKind::Equal, "conflict document last block equal");
    expectLine(doc.blocks[0].leftLines, 0, "before", "conflict document before line");
    expectLine(doc.blocks[1].leftLines, 0, "ours", "conflict document ours line");
    expectLine(doc.blocks[1].rightLines, 0, "theirs", "conflict document theirs line");
    expectLine(doc.blocks[2].leftLines, 0, "after", "conflict document after line");
    expect(!macdiff::canMerge(doc), "conflict document cannot merge before resolution");

    doc.blocks[1].pick = PickSide::Manual;
    doc.blocks[1].manualLines = {"resolved"};
    expect(macdiff::mergeText(doc) == "before\nresolved\nafter\n", "conflict document manual merge output");
}

void testConflictDocumentParsingMultipleAndDiff3() {
    auto doc = macdiff::buildConflictDocument(
        "top\n"
        "<<<<<<< ours\n"
        "left one\n"
        "||||||| base\n"
        "base one\n"
        "=======\n"
        "right one\n"
        ">>>>>>> theirs\n"
        "middle\n"
        "<<<<<<< ours\n"
        "left two\n"
        "=======\n"
        "right two\n"
        ">>>>>>> theirs\n"
        "bottom\n");

    expect(doc.blocks.size() == 5, "multiple conflict document block count");
    expect(doc.blocks[1].kind == DiffBlockKind::Changed, "diff3 first conflict changed");
    expect(doc.blocks[3].kind == DiffBlockKind::Changed, "second conflict changed");
    expectLine(doc.blocks[1].leftLines, 0, "left one", "diff3 left line");
    expectLine(doc.blocks[1].rightLines, 0, "right one", "diff3 right line");
    expectLine(doc.blocks[3].leftLines, 0, "left two", "second conflict left line");
    expectLine(doc.blocks[3].rightLines, 0, "right two", "second conflict right line");
    expect(doc.blocks[1].rightLines.size() == 1, "diff3 base lines are ignored");
}

void testConflictDocumentRejectsMalformedMarkers() {
    expectThrows<std::runtime_error>([] {
        (void)macdiff::buildConflictDocument(
            "<<<<<<< ours\n"
            "left\n"
            ">>>>>>> theirs\n");
    }, "conflict document missing separator");

    expectThrows<std::runtime_error>([] {
        (void)macdiff::buildConflictDocument(
            "=======\n"
            "orphan\n");
    }, "conflict document orphan separator");
}

void testInvalidBlocksAndPickValidation() {
    DiffDocument invalid;
    DiffBlock block;
    invalid.blocks.push_back(block);

    expect(!macdiff::canMerge(invalid), "invalid block cannot merge");
    expectThrows<std::runtime_error>([&] { (void)macdiff::mergeText(invalid); }, "invalid block merge");

    DiffDocument unpicked;
    unpicked.blocks.push_back(changedBlock({"left"}, {"right"}));
    expect(!macdiff::canMerge(unpicked), "unpicked changed block cannot merge");
    expectThrows<std::runtime_error>([&] { (void)macdiff::mergeText(unpicked); }, "unpicked changed block merge");

    DiffDocument pickedDeletion;
    pickedDeletion.blocks.push_back(changedBlock({"gone"}, {}, PickSide::Right));
    expect(macdiff::canMerge(pickedDeletion), "picked deletion can merge");
    expect(macdiff::mergeText(pickedDeletion).empty(), "picked deletion merge output");

    DiffDocument pickedInsertion;
    pickedInsertion.blocks.push_back(changedBlock({}, {"new"}, PickSide::Right));
    expect(macdiff::canMerge(pickedInsertion), "picked insertion can merge");
    expect(macdiff::mergeText(pickedInsertion) == "new\n", "picked insertion merge output");

    DiffDocument manual;
    auto manualBlock = changedBlock({"left"}, {"right"}, PickSide::Manual);
    manualBlock.manualLines = {"custom", "merged"};
    manual.blocks.push_back(manualBlock);
    expect(macdiff::canMerge(manual), "manual changed block can merge");
    expect(macdiff::mergeText(manual) == "custom\nmerged\n", "manual changed block merge output");

    DiffDocument emptyManual;
    auto emptyManualBlock = changedBlock({"left"}, {"right"}, PickSide::Manual);
    emptyManual.blocks.push_back(emptyManualBlock);
    expect(macdiff::canMerge(emptyManual), "empty manual changed block can merge");
    expect(macdiff::mergeText(emptyManual).empty(), "empty manual changed block merge output");

    DiffDocument manualEqual;
    DiffBlock equalBlock;
    equalBlock.kind = DiffBlockKind::Equal;
    equalBlock.leftLines = {"original"};
    equalBlock.rightLines = {"original"};
    equalBlock.manualLines = {"edited"};
    equalBlock.pick = PickSide::Manual;
    manualEqual.blocks.push_back(equalBlock);
    expect(macdiff::canMerge(manualEqual), "manual equal block can merge");
    expect(macdiff::mergeText(manualEqual) == "edited\n", "manual equal block merge output");
}

}

int main() {
    testEqualDocument();
    testEmptyDocuments();
    testReplacementAndMergeChoices();
    testInsertionAtBeginningMiddleAndEnd();
    testDeletionAtBeginningMiddleAndEnd();
    testMultilineReplacementAndBlankLines();
    testMultipleIndependentHunks();
    testConflictDocumentParsing();
    testConflictDocumentParsingMultipleAndDiff3();
    testConflictDocumentRejectsMalformedMarkers();
    testInvalidBlocksAndPickValidation();

    if (failures != 0) {
        std::cerr << failures << " core test failure(s)\n";
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
