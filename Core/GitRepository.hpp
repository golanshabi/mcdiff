#pragma once

#include <string>
#include <vector>

namespace macdiff {

struct GitFile {
    std::string relativePath;
    std::string headRelativePath;
    bool isTextConflict = false;
    bool isConflict = false;
    std::string message;
    std::string statusDescription;
};

std::string discoverGitRepository(const std::string& startPath);
std::vector<GitFile> gitConflictFiles(const std::string& repositoryRoot);
std::vector<GitFile> gitChangedFiles(const std::string& repositoryRoot);
std::string gitHeadFileText(const std::string& repositoryRoot, const std::string& relativePath);
void gitStageFile(const std::string& repositoryRoot, const std::string& relativePath);

}
