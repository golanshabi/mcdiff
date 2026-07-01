#include "ConflictParser.hpp"
#include "Logger.hpp"

#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace macdiff {
namespace {

enum class ParserState {
    Equal,
    Left,
    Base,
    Right
};

bool startsWith(const std::string& text, const char* prefix) {
    const std::string needle(prefix);
    return text.size() >= needle.size() && text.compare(0, needle.size(), needle) == 0;
}

std::vector<std::string> linesOf(const std::string& text) {
    std::vector<std::string> lines;
    std::stringstream stream(text);
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(line);
    }
    return lines;
}

void flushEqual(DiffDocument& doc,
                std::vector<std::string>& equalLines,
                LineNumber startLine) {
    if (equalLines.empty()) return;

    DiffBlock block;
    block.kind = DiffBlockKind::Equal;
    block.leftStartLine = startLine;
    block.rightStartLine = startLine;
    block.leftLines = equalLines;
    block.rightLines = equalLines;
    doc.blocks.push_back(block);
    equalLines.clear();
}

void addConflict(DiffDocument& doc,
                 std::vector<std::string>& leftLines,
                 std::vector<std::string>& rightLines,
                 LineNumber startLine) {
    DiffBlock block;
    block.kind = DiffBlockKind::Changed;
    block.leftStartLine = startLine;
    block.rightStartLine = startLine;
    block.leftLines = leftLines;
    block.rightLines = rightLines;
    block.pick = PickSide::Unpicked;
    doc.blocks.push_back(block);
    leftLines.clear();
    rightLines.clear();
}

}

DiffDocument buildConflictDocument(const std::string& worktreeText) {
    DiffDocument doc;
    std::vector<std::string> equalLines;
    std::vector<std::string> leftLines;
    std::vector<std::string> rightLines;

    ParserState state = ParserState::Equal;
    LineNumber equalStartLine = 1;
    LineNumber conflictStartLine = 1;
    LineNumber outputLine = 1;

    for (const auto& line : linesOf(worktreeText)) {
        switch (state) {
            case ParserState::Equal:
                if (startsWith(line, "<<<<<<<")) {
                    flushEqual(doc, equalLines, equalStartLine);
                    conflictStartLine = outputLine;
                    state = ParserState::Left;
                } else if (startsWith(line, "=======") ||
                           startsWith(line, ">>>>>>>") ||
                           startsWith(line, "|||||||")) {
                    MCD_LOG_ERROR("Malformed conflict markers while reading equal content.");
                    throw std::runtime_error("Malformed conflict markers.");
                } else {
                    if (equalLines.empty()) equalStartLine = outputLine;
                    equalLines.push_back(line);
                    ++outputLine;
                }
                break;

            case ParserState::Left:
                if (startsWith(line, "|||||||")) {
                    state = ParserState::Base;
                } else if (startsWith(line, "=======")) {
                    state = ParserState::Right;
                } else if (startsWith(line, "<<<<<<<") ||
                           startsWith(line, ">>>>>>>")) {
                    MCD_LOG_ERROR("Malformed conflict markers while reading left side.");
                    throw std::runtime_error("Malformed conflict markers.");
                } else {
                    leftLines.push_back(line);
                }
                break;

            case ParserState::Base:
                if (startsWith(line, "=======")) {
                    state = ParserState::Right;
                } else if (startsWith(line, "<<<<<<<") ||
                           startsWith(line, ">>>>>>>")) {
                    MCD_LOG_ERROR("Malformed conflict markers while reading base side.");
                    throw std::runtime_error("Malformed conflict markers.");
                }
                break;

            case ParserState::Right:
                if (startsWith(line, ">>>>>>>")) {
                    const auto resolvedLineCount = static_cast<LineNumber>(rightLines.size());
                    addConflict(doc, leftLines, rightLines, conflictStartLine);
                    outputLine += resolvedLineCount;
                    equalStartLine = outputLine;
                    state = ParserState::Equal;
                } else if (startsWith(line, "<<<<<<<") ||
                           startsWith(line, "=======") ||
                           startsWith(line, "|||||||")) {
                    MCD_LOG_ERROR("Malformed conflict markers while reading right side.");
                    throw std::runtime_error("Malformed conflict markers.");
                } else {
                    rightLines.push_back(line);
                }
                break;
        }
    }

    if (state != ParserState::Equal) {
        MCD_LOG_ERROR("Malformed conflict markers at end of file.");
        throw std::runtime_error("Malformed conflict markers.");
    }

    flushEqual(doc, equalLines, equalStartLine);
    return doc;
}

}
