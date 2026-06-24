#include "DiffEngine.hpp"
#include "Logger.hpp"

#include <git2.h>

#include <sstream>
#include <stdexcept>

namespace macdiff {
namespace {

std::vector<std::string> linesOf(const std::string& text) {
    std::vector<std::string> lines;
    std::stringstream stream(text);
    std::string line;
    while (std::getline(stream, line)) lines.push_back(line);
    return lines;
}

LineNumber toLineNumber(int line) {
    return line < 0 ? InvalidLineNumber : static_cast<LineNumber>(line);
}

int equalLineCountBeforeHunk(int cursor, int hunkStart, int hunkLines) {
    // A zero-length side is anchored to the line before the insertion/deletion.
    // Include that anchor in the preceding equal block so the final document
    // keeps all unchanged lines in order.
    const int anchorAdjustment = hunkLines == 0 ? 1 : 0;
    return hunkStart - cursor + anchorAdjustment;
}

int cursorAfterHunk(int hunkStart, int hunkLines) {
    const int zeroLengthAnchor = hunkLines == 0 ? 1 : 0;
    return hunkStart + hunkLines + zeroLengthAnchor;
}

void addEqual(DiffDocument& doc,
              const std::vector<std::string>& left,
              const std::vector<std::string>& right,
              int leftStart,
              int rightStart,
              int count) {
    if (count <= 0) return;

    DiffBlock block;
    block.kind = DiffBlockKind::Equal;
    block.leftStartLine = leftStart;
    block.rightStartLine = rightStart;
    for (int i = 0; i < count; ++i) {
        block.leftLines.push_back(left[leftStart - 1 + i]);
        block.rightLines.push_back(right[rightStart - 1 + i]);
    }
    doc.blocks.push_back(block);
}

std::string cleanLine(const git_diff_line* line) {
    std::string text(line->content, line->content_len);
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) text.pop_back();
    return text;
}

struct Libgit2Runtime {
    Libgit2Runtime() {
        if (git_libgit2_init() < 0) {
            MCD_LOG_ERROR("Failed to initialize libgit2.");
            throw std::runtime_error("Failed to initialize libgit2.");
        }
        MCD_LOG_INFO("Initialized libgit2 runtime.");
    }

    ~Libgit2Runtime() {
        git_libgit2_shutdown();
        MCD_LOG_INFO("Shut down libgit2 runtime.");
    }
};

void ensureLibgit2Runtime() {
    // Function-local statics are initialized once and destroyed at process exit,
    // which keeps libgit2 alive for every diff without repeatedly changing its
    // global reference count.
    static Libgit2Runtime runtime;
}

struct State {
    DiffDocument doc;
    std::vector<std::string> left;
    std::vector<std::string> right;
    int leftCursor = 1;
    int rightCursor = 1;
};

int onHunk(const git_diff_delta*, const git_diff_hunk* hunk, void* payload) {
    auto* state = static_cast<State*>(payload);
    MCD_LOG_INFO("Processing hunk old_start=" + std::to_string(hunk->old_start) +
                 " old_lines=" + std::to_string(hunk->old_lines) +
                 " new_start=" + std::to_string(hunk->new_start) +
                 " new_lines=" + std::to_string(hunk->new_lines));
    // With zero context lines, libgit2 reports only changed regions. The cursor
    // gap before each hunk is therefore the unchanged block we need to preserve.
    addEqual(state->doc, state->left, state->right, state->leftCursor, state->rightCursor,
             equalLineCountBeforeHunk(state->leftCursor, hunk->old_start, hunk->old_lines));

    DiffBlock block;
    block.kind = DiffBlockKind::Changed;
    block.leftStartLine = toLineNumber(hunk->old_start);
    block.rightStartLine = toLineNumber(hunk->new_start);
    state->doc.blocks.push_back(block);

    state->leftCursor = cursorAfterHunk(hunk->old_start, hunk->old_lines);
    state->rightCursor = cursorAfterHunk(hunk->new_start, hunk->new_lines);
    return 0;
}

int onLine(const git_diff_delta*, const git_diff_hunk*, const git_diff_line* line, void* payload) {
    auto* state = static_cast<State*>(payload);
    if (state->doc.blocks.empty()) return 0;

    auto& block = state->doc.blocks.back();
    const char origin = line->origin;
    const std::string text = cleanLine(line);
    if (origin == GIT_DIFF_LINE_DELETION) block.leftLines.push_back(text);
    if (origin == GIT_DIFF_LINE_ADDITION) block.rightLines.push_back(text);
    return 0;
}

}

DiffDocument buildDiff(const std::string& leftText, const std::string& rightText) {
    ensureLibgit2Runtime();
    MCD_LOG_INFO("Building diff left_bytes=" + std::to_string(leftText.size()) +
                 " right_bytes=" + std::to_string(rightText.size()));

    State state;
    state.left = linesOf(leftText);
    state.right = linesOf(rightText);

    git_diff_options options = GIT_DIFF_OPTIONS_INIT;
    options.context_lines = 0;

    int result = git_diff_buffers(leftText.data(), leftText.size(), "left",
                                  rightText.data(), rightText.size(), "right",
                                  &options, nullptr, nullptr, onHunk, onLine, &state);

    if (result != 0) {
        const git_error* error = git_error_last();
        MCD_LOG_ERROR(error && error->message ? error->message : "libgit2 diff failed.");
        throw std::runtime_error(error && error->message ? error->message : "libgit2 diff failed.");
    }

    addEqual(state.doc, state.left, state.right, state.leftCursor, state.rightCursor,
             static_cast<int>(state.left.size()) - state.leftCursor + 1);
    MCD_LOG_INFO("Built diff blocks=" + std::to_string(state.doc.blocks.size()));
    return state.doc;
}

}
