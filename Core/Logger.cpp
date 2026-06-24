#include "Logger.hpp"

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <sstream>
#include <thread>

#include <unistd.h>

namespace macdiff {
namespace {

std::filesystem::path& configuredLogDirectory() {
    static std::filesystem::path directory;
    return directory;
}

std::string runDirectoryName() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t nowTime = std::chrono::system_clock::to_time_t(now);

    std::tm localTime{};
    localtime_r(&nowTime, &localTime);

    std::ostringstream stream;
    stream << std::put_time(&localTime, "%Y-%m-%d:%H:%M:%S") << "_" << getpid();
    return stream.str();
}

std::filesystem::path preferredBaseDirectory() {
    const char* home = std::getenv("HOME");
    return home ? std::filesystem::path(home) / "Library" / "Logs" / "mcdiff"
                : std::filesystem::temp_directory_path() / "mcdiff";
}

std::filesystem::path createRunDirectory(const std::filesystem::path& baseDirectory) {
    std::filesystem::create_directories(baseDirectory);
    std::filesystem::path directory = baseDirectory / runDirectoryName();
    std::filesystem::create_directories(directory);
    std::ofstream stream(directory / "cpp.log", std::ios::app);
    if (!stream) {
        throw std::runtime_error("Failed to create C++ log file: " + (directory / "cpp.log").string());
    }
    return directory;
}

std::filesystem::path runDirectory() {
    if (!configuredLogDirectory().empty()) {
        return configuredLogDirectory();
    }

    static const std::filesystem::path directory = [] {
        try {
            return createRunDirectory(preferredBaseDirectory());
        } catch (const std::filesystem::filesystem_error&) {
            return createRunDirectory(std::filesystem::temp_directory_path() / "mcdiff");
        }
    }();

    return directory;
}

std::filesystem::path logPath() {
    return runDirectory() / "cpp.log";
}

std::string timestamp() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t nowTime = std::chrono::system_clock::to_time_t(now);

    std::tm localTime{};
    localtime_r(&nowTime, &localTime);

    std::ostringstream stream;
    stream << std::put_time(&localTime, "%Y-%m-%d %H:%M:%S");
    return stream.str();
}

const char* levelName(LogLevel level) {
    switch (level) {
        case LogLevel::Info:
            return "INFO";
        case LogLevel::Error:
            return "ERROR";
    }
}

std::string fileName(const char* path) {
    return std::filesystem::path(path).filename().string();
}

void waitForLogDirectory(const std::filesystem::path& path) {
    for (int attempt = 1; attempt <= 10; ++attempt) {
        if (std::filesystem::exists(path)) {
            return;
        }

        std::fprintf(stderr,
                     "mcdiff logging waiting for log directory attempt=%d path=%s\n",
                     attempt,
                     path.string().c_str());
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    if (!std::filesystem::exists(path)) {
        throw std::runtime_error("Log directory does not exist after 10 seconds: " + path.string());
    }
}

}

void setLogDirectory(const std::string& directory) {
    if (directory.empty()) {
        throw std::invalid_argument("Log directory path is empty");
    }

    std::filesystem::path path(directory);
    waitForLogDirectory(path);
    if (!std::filesystem::is_directory(path)) {
        throw std::runtime_error("Log path is not a directory: " + path.string());
    }

    std::filesystem::path cppLogPath = path / "cpp.log";
    if (!std::filesystem::exists(cppLogPath)) {
        throw std::runtime_error("C++ log file does not exist: " + cppLogPath.string());
    }
    std::ofstream stream(cppLogPath, std::ios::app);
    if (!stream) {
        throw std::runtime_error("Failed to open C++ log file: " + cppLogPath.string());
    }

    configuredLogDirectory() = path;
}

void writeLog(LogLevel level, const char* file, const char* function, int line, const std::string& message) {
    const std::filesystem::path path = logPath();
    std::ofstream stream(path, std::ios::app);
    if (!stream) {
        throw std::runtime_error("Failed to open log file: " + path.string());
    }

    stream << timestamp()
           << " [" << levelName(level) << "] "
           << fileName(file) << ":" << function << ":" << line
           << " - " << message << '\n';
}

}
