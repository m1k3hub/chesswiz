#include "scidb_lockdown.h"
#ifdef CQL6_EMBEDDED
#include "cqlexception.h"
#include <string>

std::atomic<bool> ScidbSearchActive{false};

namespace scidb {
void file_guard(const char* what, const char* path) {
    if (ScidbSearchActive.load(std::memory_order_relaxed)) {
        throw CqlException(std::string("filesystem access is not available when CQL runs inside Scidb (")
                           + what + (path ? std::string(": ") + path : std::string()) + ")");
    }
}
}
#endif
