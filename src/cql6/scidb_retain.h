#pragma once
// scidb: heap objects in the parse forest belong to one search. Shared raw
// pointers are non-owning; cleanup deletes each allocation exactly once.
#ifdef CQL6_EMBEDDED
#include <cstddef>
enum class ScidbObject { Node, Token, Environment, Range, Transform, DirectionParameter };
void* scidb_allocate(std::size_t size, ScidbObject kind);
void scidb_deallocate(void* object) noexcept;
void scidb_release_search_objects() noexcept;
#define SCIDB_SEARCH_ALLOCATOR(kind) \
  static void* operator new(std::size_t size) { return scidb_allocate(size, ScidbObject::kind); } \
  static void operator delete(void* p) noexcept { scidb_deallocate(p); }
#endif
