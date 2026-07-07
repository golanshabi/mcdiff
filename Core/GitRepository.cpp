#include "GitRepository.hpp"
#include "Logger.hpp"

#include <git2.h>

#include <algorithm>
#include <set>
#include <stdexcept>

namespace macdiff {
namespace {

std::runtime_error gitError(const char *fallback) {
    const git_error *error = git_error_last();
    return std::runtime_error(error && error->message ? error->message : fallback);
}

struct Libgit2GitRuntime {
    Libgit2GitRuntime() {
        if (git_libgit2_init() < 0) {
            throw std::runtime_error("Failed to initialize libgit2.");
        }
        MCD_LOG_INFO("Initialized git repository libgit2 runtime.");
    }

    ~Libgit2GitRuntime() {
        git_libgit2_shutdown();
        MCD_LOG_INFO("Shut down git repository libgit2 runtime.");
    }
};

void ensureGitRuntime() {
    static Libgit2GitRuntime runtime;
}

std::string conflictPath(const git_index_entry *ancestor,
                         const git_index_entry *ours,
                         const git_index_entry *theirs) {
    if (ours && ours->path) return ours->path;
    if (theirs && theirs->path) return theirs->path;
    if (ancestor && ancestor->path) return ancestor->path;
    return "";
}

GitFile gitFile(const std::string& relativePath,
                const std::string& headRelativePath,
                bool isConflict,
                const std::string& statusDescription,
                const std::string& message = "") {
    GitFile file;
    file.relativePath = relativePath;
    file.headRelativePath = headRelativePath;
    file.isTextConflict = isConflict;
    file.isConflict = isConflict;
    file.message = message;
    file.statusDescription = statusDescription;
    return file;
}

std::string statusDescription(unsigned int status) {
    std::vector<std::string> parts;
    if (status & GIT_STATUS_CONFLICTED) parts.push_back("conflict");
    if (status & GIT_STATUS_INDEX_NEW) parts.push_back("staged added");
    if (status & GIT_STATUS_INDEX_MODIFIED) parts.push_back("staged modified");
    if (status & GIT_STATUS_INDEX_DELETED) parts.push_back("staged deleted");
    if (status & GIT_STATUS_INDEX_RENAMED) parts.push_back("staged renamed");
    if (status & GIT_STATUS_INDEX_TYPECHANGE) parts.push_back("staged type changed");
    if (status & GIT_STATUS_WT_NEW) parts.push_back("untracked");
    if (status & GIT_STATUS_WT_MODIFIED) parts.push_back("modified");
    if (status & GIT_STATUS_WT_DELETED) parts.push_back("deleted");
    if (status & GIT_STATUS_WT_RENAMED) parts.push_back("renamed");
    if (status & GIT_STATUS_WT_TYPECHANGE) parts.push_back("type changed");
    if (status & GIT_STATUS_WT_UNREADABLE) parts.push_back("unreadable");
    if (parts.empty()) return "modified";

    std::string text = parts[0];
    for (std::size_t index = 1; index < parts.size(); ++index) {
        text += ", " + parts[index];
    }
    return text;
}

const char *newPath(const git_diff_delta *delta) {
    if (!delta) return nullptr;
    if (delta->new_file.path) return delta->new_file.path;
    return delta->old_file.path;
}

const char *oldPath(const git_diff_delta *delta) {
    if (!delta) return nullptr;
    if (delta->old_file.path) return delta->old_file.path;
    return delta->new_file.path;
}

std::string displayPath(const git_status_entry *entry) {
    if (!entry) return "";
    const git_diff_delta *delta = entry->index_to_workdir ? entry->index_to_workdir : entry->head_to_index;
    const char *path = newPath(delta);
    return path ? path : "";
}

std::string headPath(const git_status_entry *entry) {
    if (!entry) return "";
    if ((entry->status & GIT_STATUS_INDEX_NEW) &&
        !(entry->status & GIT_STATUS_INDEX_RENAMED)) {
        return "";
    }
    if (entry->status & GIT_STATUS_WT_NEW) {
        return "";
    }
    const git_diff_delta *delta = entry->head_to_index ? entry->head_to_index : entry->index_to_workdir;
    const char *path = oldPath(delta);
    return path ? path : "";
}

void sortFiles(std::vector<GitFile>& files) {
    std::sort(files.begin(), files.end(), [](const GitFile& left, const GitFile& right) {
        return left.relativePath < right.relativePath;
    });
}

}

std::string discoverGitRepository(const std::string& startPath) {
    ensureGitRuntime();
    git_repository *repo = nullptr;
    if (git_repository_open_ext(&repo, startPath.c_str(), 0, nullptr) != 0) {
        throw gitError("No git repository found.");
    }

    const char *workdir = git_repository_workdir(repo);
    if (!workdir) {
        git_repository_free(repo);
        throw std::runtime_error("Bare git repositories are not supported.");
    }

    std::string path = workdir;
    git_repository_free(repo);
    MCD_LOG_INFO("Discovered git repository root=" + path);
    return path;
}

std::vector<GitFile> gitConflictFiles(const std::string& repositoryRoot) {
    ensureGitRuntime();
    git_repository *repo = nullptr;
    if (git_repository_open(&repo, repositoryRoot.c_str()) != 0) {
        throw gitError("Could not open git repository.");
    }

    git_index *index = nullptr;
    if (git_repository_index(&index, repo) != 0) {
        git_repository_free(repo);
        throw gitError("Could not read git index.");
    }

    git_index_conflict_iterator *iterator = nullptr;
    int iteratorResult = git_index_conflict_iterator_new(&iterator, index);
    if (iteratorResult != 0) {
        git_index_free(index);
        git_repository_free(repo);
        if (iteratorResult == GIT_ENOTFOUND) return {};
        throw gitError("Could not inspect git conflicts.");
    }

    std::vector<GitFile> files;
    const git_index_entry *ancestor = nullptr;
    const git_index_entry *ours = nullptr;
    const git_index_entry *theirs = nullptr;
    while (git_index_conflict_next(&ancestor, &ours, &theirs, iterator) == 0) {
        const std::string path = conflictPath(ancestor, ours, theirs);
        if (path.empty()) continue;
        files.push_back(gitFile(path, path, true, "conflict"));
    }

    git_index_conflict_iterator_free(iterator);
    git_index_free(index);
    git_repository_free(repo);

    sortFiles(files);
    MCD_LOG_INFO("Listed git conflict files count=" + std::to_string(files.size()));
    return files;
}

std::vector<GitFile> gitChangedFiles(const std::string& repositoryRoot) {
    std::vector<GitFile> files = gitConflictFiles(repositoryRoot);
    std::set<std::string> seenPaths;
    for (const auto& file : files) {
        seenPaths.insert(file.relativePath);
    }

    ensureGitRuntime();
    git_repository *repo = nullptr;
    if (git_repository_open(&repo, repositoryRoot.c_str()) != 0) {
        throw gitError("Could not open git repository.");
    }

    git_status_options options = GIT_STATUS_OPTIONS_INIT;
    options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED |
                    GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS |
                    GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
                    GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR |
                    GIT_STATUS_OPT_SORT_CASE_SENSITIVELY;

    git_status_list *statusList = nullptr;
    if (git_status_list_new(&statusList, repo, &options) != 0) {
        git_repository_free(repo);
        throw gitError("Could not inspect git changes.");
    }

    const size_t count = git_status_list_entrycount(statusList);
    for (size_t i = 0; i < count; ++i) {
        const git_status_entry *entry = git_status_byindex(statusList, i);
        if (!entry || entry->status == GIT_STATUS_CURRENT || (entry->status & GIT_STATUS_IGNORED)) continue;
        if (entry->status & GIT_STATUS_CONFLICTED) continue;

        const std::string path = displayPath(entry);
        if (path.empty() || seenPaths.find(path) != seenPaths.end()) continue;

        files.push_back(gitFile(path,
                                headPath(entry),
                                false,
                                statusDescription(entry->status)));
        seenPaths.insert(path);
    }

    git_status_list_free(statusList);
    git_repository_free(repo);

    sortFiles(files);
    MCD_LOG_INFO("Listed git changed files count=" + std::to_string(files.size()));
    return files;
}

std::string gitHeadFileText(const std::string& repositoryRoot, const std::string& relativePath) {
    if (relativePath.empty()) return "";

    ensureGitRuntime();
    git_repository *repo = nullptr;
    if (git_repository_open(&repo, repositoryRoot.c_str()) != 0) {
        throw gitError("Could not open git repository.");
    }

    git_object *treeObject = nullptr;
    const int treeResult = git_revparse_single(&treeObject, repo, "HEAD^{tree}");
    if (treeResult == GIT_ENOTFOUND || treeResult == GIT_EUNBORNBRANCH) {
        git_repository_free(repo);
        return "";
    }
    if (treeResult != 0 || !treeObject || git_object_type(treeObject) != GIT_OBJECT_TREE) {
        if (treeObject) git_object_free(treeObject);
        git_repository_free(repo);
        throw gitError("Could not read HEAD tree.");
    }

    git_tree *tree = reinterpret_cast<git_tree *>(treeObject);
    git_tree_entry *entry = nullptr;
    const int entryResult = git_tree_entry_bypath(&entry, tree, relativePath.c_str());
    if (entryResult == GIT_ENOTFOUND) {
        git_object_free(treeObject);
        git_repository_free(repo);
        return "";
    }
    if (entryResult != 0) {
        git_object_free(treeObject);
        git_repository_free(repo);
        throw gitError("Could not read file from HEAD.");
    }

    if (git_tree_entry_type(entry) != GIT_OBJECT_BLOB) {
        git_tree_entry_free(entry);
        git_object_free(treeObject);
        git_repository_free(repo);
        throw std::runtime_error("Only text file blobs can be diffed from HEAD.");
    }

    git_blob *blob = nullptr;
    if (git_blob_lookup(&blob, repo, git_tree_entry_id(entry)) != 0) {
        git_tree_entry_free(entry);
        git_object_free(treeObject);
        git_repository_free(repo);
        throw gitError("Could not read file blob from HEAD.");
    }

    const char *content = static_cast<const char *>(git_blob_rawcontent(blob));
    const git_object_size_t size = git_blob_rawsize(blob);
    std::string text(content, content + size);
    git_blob_free(blob);
    git_tree_entry_free(entry);
    git_object_free(treeObject);
    git_repository_free(repo);
    return text;
}

void gitStageFile(const std::string& repositoryRoot, const std::string& relativePath) {
    ensureGitRuntime();
    git_repository *repo = nullptr;
    if (git_repository_open(&repo, repositoryRoot.c_str()) != 0) {
        throw gitError("Could not open git repository.");
    }

    git_index *index = nullptr;
    if (git_repository_index(&index, repo) != 0) {
        git_repository_free(repo);
        throw gitError("Could not read git index.");
    }

    if (git_index_add_bypath(index, relativePath.c_str()) != 0 ||
        git_index_write(index) != 0) {
        git_index_free(index);
        git_repository_free(repo);
        throw gitError("Could not stage resolved file.");
    }

    git_index_free(index);
    git_repository_free(repo);
    MCD_LOG_INFO("Staged git file relative_path=" + relativePath);
}

}
