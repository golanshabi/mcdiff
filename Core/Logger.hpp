#pragma once

#include <string>

namespace macdiff {

enum class LogLevel { Info, Error };

void setLogDirectory(const std::string& directory);
void writeLog(LogLevel level, const char* file, const char* function, int line, const std::string& message);

}

#if defined(MCD_LOGGING_DISABLED)
#define MCD_LOG_INFO(message) do {} while (false)
#define MCD_LOG_ERROR(message) do {} while (false)
#else
#define MCD_LOG_INFO(message) ::macdiff::writeLog(::macdiff::LogLevel::Info, __FILE__, __func__, __LINE__, (message))
#define MCD_LOG_ERROR(message) ::macdiff::writeLog(::macdiff::LogLevel::Error, __FILE__, __func__, __LINE__, (message))
#endif
