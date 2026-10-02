// scidb: implementation of the embedded output sink (see scidb_sink.h).
// Compiled like every library TU with the sink macros force-included, so this
// file must not itself use printf/cout (it doesn't).
#include "scidb_sink.h"

#if defined(CQL6_EMBEDDED) && defined(CQL6_LIBRARY_BUILD)

// this TU implements the sink itself: undo the redirection macros so the real
// stdio functions can be called for non-stdout/stderr streams
#undef printf
#undef fprintf
#undef puts
#undef fputs
#undef putchar
#undef putc
#undef fputc
#undef cout
#undef cerr
#undef clog

#include <mutex>
#include <string>
#include <vector>
#include <cstdarg>
#include <cstring>

namespace scidb_sink {

static std::mutex g_mutex;
static std::string g_buffer;
static bool g_active = false;
static bool g_truncated = false;
static const size_t MAXBUF = 4u * 1024u * 1024u; // 4 MB cap on captured text

static void append_locked(const char* s, size_t n) {
    if (g_buffer.size() + n > MAXBUF) {
        if (g_buffer.size() < MAXBUF) {
            n = MAXBUF - g_buffer.size();
            g_buffer.append(s, n);
        }
        if (!g_truncated) {
            g_truncated = true;
            g_buffer.append("\n[scidb: captured library output truncated at 4 MB]\n");
        }
        return;
    }
    g_buffer.append(s, n);
}

static void sink_append(const char* s, size_t n) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (!g_active) return; // outside a search: drop everything
    append_locked(s, n);
}

void begin() {
    std::lock_guard<std::mutex> lk(g_mutex);
    g_buffer.clear();
    g_truncated = false;
    g_active = true;
}

std::string end() {
    std::lock_guard<std::mutex> lk(g_mutex);
    g_active = false;
    std::string out;
    out.swap(g_buffer);
    return out;
}

class SinkBuf : public std::streambuf {
protected:
    int overflow(int c) override {
        if (c != EOF) {
            char ch = (char)c;
            sink_append(&ch, 1);
        }
        return c;
    }
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        sink_append(s, (size_t)n);
        return n;
    }
};

static SinkBuf g_sinkbuf;

std::ostream& scout() {
    static std::ostream os(&g_sinkbuf);
    return os;
}

static int sink_vprintf(const char* fmt, va_list ap) {
    char tmp[2048];
    va_list ap2;
    va_copy(ap2, ap);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap2);
    va_end(ap2);
    if (n < 0) return n;
    if ((size_t)n < sizeof(tmp)) {
        sink_append(tmp, (size_t)n);
    } else {
        std::vector<char> big((size_t)n + 1);
        va_list ap3;
        va_copy(ap3, ap);
        int n2 = vsnprintf(big.data(), big.size(), fmt, ap3);
        va_end(ap3);
        if (n2 > 0) sink_append(big.data(), (size_t)n2);
    }
    return n;
}

int sink_printf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = sink_vprintf(fmt, ap);
    va_end(ap);
    return r;
}

int sink_fprintf(void* stream, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r;
    if (stream == (void*)stdout || stream == (void*)stderr || stream == NULL) {
        r = sink_vprintf(fmt, ap);
    } else {
        r = vfprintf((FILE*)stream, fmt, ap);
    }
    va_end(ap);
    return r;
}

int sink_puts(const char* s) {
    if (!s) return EOF;
    size_t n = strlen(s);
    sink_append(s, n);
    sink_append("\n", 1);
    return (int)n + 1;
}

int sink_fputs(const char* s, void* stream) {
    if (!s) return EOF;
    if (stream == (void*)stdout || stream == (void*)stderr || stream == NULL) {
        sink_append(s, strlen(s));
        return 0;
    }
    return fputs(s, (FILE*)stream);
}

int sink_putchar(int c) {
    char ch = (char)c;
    sink_append(&ch, 1);
    return c;
}

int sink_putc(int c, void* stream) {
    if (stream == (void*)stdout || stream == (void*)stderr || stream == NULL) {
        char ch = (char)c;
        sink_append(&ch, 1);
        return c;
    }
    return fputc(c, (FILE*)stream);
}

} // namespace scidb_sink

#endif // CQL6_EMBEDDED
