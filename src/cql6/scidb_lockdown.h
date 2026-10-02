#pragma once
// scidb: embedded file lockdown (Task 3 §A).
// While a cql6_search is running, no code path in the library may open, read,
// write, create, rename or delete a file. Every filesystem entry point that is
// compiled into the library calls scidb::file_guard(); during a search it throws
// a CqlException instead of touching the filesystem. Disabled language constructs
// (writefile/readfile) additionally fail at PARSE time so no partial run happens.
// Outside a search (e.g. the test driver's own PGN loading through the vendored
// PgnSource/MFile classes) the guard is inactive.
#ifdef CQL6_EMBEDDED
#include <atomic>

extern std::atomic<bool> ScidbSearchActive; // true from entry to exit of cql6_search

namespace scidb {
void file_guard(const char* what, const char* path);
}
#endif
