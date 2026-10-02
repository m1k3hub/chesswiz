// scidb: explicit allocation ownership for the embedded parse forest.
#include "scidb_retain.h"
#ifdef CQL6_EMBEDDED
#include "node.h"
#include "environment.h"
#include "range.h"
#include "transform.h"
#include <map>
#include <mutex>
#include <new>
namespace {
std::mutex objects_mutex;
std::map<void*, ScidbObject> objects;
}
void* scidb_allocate(std::size_t size, ScidbObject kind) {
    void* object = ::operator new(size);
    try {
        std::lock_guard<std::mutex> lock(objects_mutex);
        objects.emplace(object, kind);
    } catch (...) { ::operator delete(object); throw; }
    return object;
}
void scidb_deallocate(void* object) noexcept {
    if (!object) return;
    {
        std::lock_guard<std::mutex> lock(objects_mutex);
        objects.erase(object);
    }
    ::operator delete(object);
}
void scidb_release_search_objects() noexcept {
    // All matching workers have joined. Objects hold shared, non-owning links;
    // their default destructors release containers but never follow those links.
    for (;;) {
        void* object;
        ScidbObject kind;
        {
            std::lock_guard<std::mutex> lock(objects_mutex);
            if (objects.empty()) break;
            auto first = objects.begin();
            object = first->first;
            kind = first->second;
            objects.erase(first);
        }
        switch (kind) {
        case ScidbObject::Node: delete static_cast<Node*>(object); break;
        case ScidbObject::Token: delete static_cast<Token*>(object); break;
        case ScidbObject::Environment: delete static_cast<Environment*>(object); break;
        case ScidbObject::Range: delete static_cast<Range*>(object); break;
        case ScidbObject::DirectionParameter: delete static_cast<DirectionParameter*>(object); break;
        case ScidbObject::Transform: delete static_cast<Transform*>(object); break;
        }
    }
    CqlParseRoot = nullptr;
    CqlGameNumberRange = CqlMatchCountRange = CqlYearRange = nullptr;
}
#endif
