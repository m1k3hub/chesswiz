// scidb: process-lifetime retention must not grow with every search.
#include "cql6_api.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>
struct Feed { int next = 0; };
static int next_game(void* ctx, int, cql6_game* game) {
    auto& feed = *static_cast<Feed*>(ctx);
    if (feed.next++) return 0;
    static const cql6_move moves[] = {{0,12,28,0,nullptr},{0,52,36,0,nullptr},{3,0,0,0,nullptr},{0,62,45,0,nullptr}};
    *game = {0,nullptr,0,nullptr,4,moves};
    return 1;
}
static long rss() {
    FILE* f = std::fopen("/proc/self/statm", "r");
    long pages = 0, resident = 0;
    if (!f || std::fscanf(f, "%ld %ld", &pages, &resident) != 2) return -1;
    std::fclose(f);
    return resident * sysconf(_SC_PAGESIZE);
}
int main(int argc, char** argv) {
    int repeats = argc > 1 ? std::atoi(argv[1]) : 3000;
    cql6_options options{};
    options.threads = 2;
    const char* scripts[] = {
        "cql() initial", "cql() flipcolor check", "cql() shift P[a2]",
        "cql() function f(){check} f()", "cql() ray (R K)",
        "cql() invalid_filter"
    };
    long baseline = 0;
    for (int i = 0; i < repeats + 100; ++i) {
        Feed feed;
        std::string script = std::string(scripts[i % 6]) + " // search " + std::to_string(i);
        cql6_result result{};
        char error[2048];
        int rc = cql6_search(script.c_str(), &options, next_game, &feed, &result, error, sizeof(error));
        if (i % 6 != 5 && rc) { std::fprintf(stderr, "%s: %s\n", script.c_str(), error); return 1; }
        if (i % 6 == 5 && !rc) return 2;
        cql6_free_result(&result);
        if (i == 99) baseline = rss();
    }
    long growth = rss() - baseline;
    std::printf("%d distinct searches; RSS growth after warmup: %ld bytes\n", repeats, growth);
    // Sanitizer quarantine is deliberately retained; LSan independently checks leaks.
#if !defined(__SANITIZE_ADDRESS__) && !defined(__SANITIZE_THREAD__)
    if (growth > 8 * 1024 * 1024) return 3;
#endif
    return 0;
}
