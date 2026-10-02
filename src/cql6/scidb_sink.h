#pragma once
// scidb: force-included (via -include) into every translation unit of the embedded
// library build. Under CQL6_EMBEDDED it redirects the C stdio output calls and
// cout/cerr to a thread-safe, per-search message sink so that the library NEVER
// writes to the host process' stdout/stderr and never dup2()s any descriptor.
//
// Output produced while a cql6_search is running is captured and returned in
// cql6_result::messages (what a script is meant to print: `message` output,
// persistent variables, informational diagnostics). Output produced outside a
// search is dropped.
//
// This header must be included BEFORE any use of the redirected names; the real
// declarations from <cstdio>/<iostream> are pulled in here first so that the
// macros below never rewrite a system declaration (glibc declares them with a
// space before '(', so even the function-like macros cannot touch them).
// CQL6_LIBRARY_BUILD is defined only when compiling the library's own translation
// units (Makefile.scidb); test drivers include these headers too but must keep the
// real printf/cout.
#if defined(CQL6_EMBEDDED) && defined(CQL6_LIBRARY_BUILD)
#ifdef __cplusplus

#include <cstdio>
#include <iostream>
#include <string>

namespace scidb_sink {

// capture control, called by cql6_api.cpp
void begin();                      // start capturing for a new search
std::string end();                 // stop capturing, return the captured text

std::ostream& scout();             // the sink stream
int sink_printf(const char* fmt, ...);
int sink_fprintf(void* stream, const char* fmt, ...);
int sink_puts(const char* s);
int sink_fputs(const char* s, void* stream);
int sink_putchar(int c);
int sink_putc(int c, void* stream);

} // namespace scidb_sink

// scidb: `cout` in every library TU is this reference to the sink stream (an inline
// variable, so headers stay usable with or without the -include). The original
// `using std::cout;` in abbreviations.h is disabled under CQL6_EMBEDDED.
inline std::ostream& cout = ::scidb_sink::scout();

#define printf ::scidb_sink::sink_printf
#define fprintf(s, ...) ::scidb_sink::sink_fprintf((void*)(s), __VA_ARGS__)
#define puts ::scidb_sink::sink_puts
#define fputs(s, st) ::scidb_sink::sink_fputs((s), (void*)(st))
#define putchar ::scidb_sink::sink_putchar
#define putc(c, st) ::scidb_sink::sink_putc((c), (void*)(st))
#define fputc(c, st) ::scidb_sink::sink_putc((c), (void*)(st))

#endif // __cplusplus
#endif // CQL6_EMBEDDED && CQL6_LIBRARY_BUILD
