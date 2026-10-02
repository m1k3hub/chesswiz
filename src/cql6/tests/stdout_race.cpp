// scidb: Task 3 §E1 test — no process-wide stdout/stderr redirect.
//
// A writer thread writes continuously to fd 1 and fd 2 while searches run.
// Gate:
//   1. every byte the writer thread emitted arrives in the captured output
//      (no swallowed/garbled lines — the old dup2-based OutputSilencer would
//      have swallowed them),
//   2. the library itself writes NOTHING to fd 1/2 (the captured file contains
//      no library output: no progress lines, no `message` filter output),
//   3. what the script is meant to print (message filter, persistent variables)
//      arrives in cql6_result::messages instead.
#include "feed_common.h"
#include <thread>
#include <atomic>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char** argv) {
    std::string pgnPath = (argc > 1) ? argv[1] : "/tmp/cql_test/mega_3000.pgn";
    Dataset ds;
    if (!fc_loadDataset(pgnPath, ds)) { std::cerr << "cannot load dataset\n"; return 2; }
    std::cerr << "loaded " << ds.games.size() << " games\n";

    // capture fd1+fd2 of this process into a temp file
    char capfile[] = "/tmp/cql_stdout_race_XXXXXX";
    int capfd = mkstemp(capfile);
    if (capfd < 0) { perror("mkstemp"); return 2; }
    fflush(stdout); fflush(stderr);
    int saved1 = dup(1), saved2 = dup(2);
    dup2(capfd, 1);
    dup2(capfd, 2);

    std::atomic<bool> stop{false};
    std::atomic<long> outSeq{0}, errSeq{0};
    std::thread writer([&]() {
        while (!stop.load(std::memory_order_relaxed)) {
            long o = outSeq.fetch_add(1) + 1;
            char buf[64];
            int n = snprintf(buf, sizeof buf, "OUTLINE-%ld\n", o);
            if (write(1, buf, (size_t)n) != n) { /* keep going */ }
            long e = errSeq.fetch_add(1) + 1;
            n = snprintf(buf, sizeof buf, "ERRLINE-%ld\n", e);
            if (write(2, buf, (size_t)n) != n) { /* keep going */ }
        }
    });

    bool ok = true;
    const char* scripts[] = {
        // message filter: the script "prints" for every matched position
        "mate and message \"scidb-mated-game\"",
        // comment + want_pgn
        "check and comment \"scidb-comment-text\"",
        // persistent variables
        "if initial\n persistent NGames += 1\nmate",
        // a plain search that in the standalone program prints progress
        "sort \"material\" ([a]<=6)",
    };
    std::vector<std::string> messages_seen;
    for (const char* s : scripts) {
        for (int threads : {1, 8}) {
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = threads;
            opt.want_pgn = 1;
            FeedContext fc;
            fc.dataset = &ds;
            fc.next_idx = 0;
            cql6_result res; char err[1024]; err[0] = 0;
            int rc = cql6_search(s, &opt, fc_feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0) {
                dprintf(saved1, "[FAIL] search error: %s\n", err);
                ok = false;
            } else if (threads == 1) {
                messages_seen.push_back(res.messages ? res.messages : "");
            }
            cql6_free_result(&res);
        }
    }

    stop.store(true);
    writer.join();
    long nOut = outSeq.load(), nErr = errSeq.load();
    fflush(stdout); fflush(stderr);
    dup2(saved1, 1); dup2(saved2, 2);
    close(saved1); close(saved2);

    // read the captured bytes
    std::string captured;
    {
        lseek(capfd, 0, SEEK_SET);
        char buf[65536];
        ssize_t n;
        while ((n = read(capfd, buf, sizeof buf)) > 0) captured.append(buf, (size_t)n);
        close(capfd);
        unlink(capfile);
    }

    // 1. every writer line arrived, in order, undamaged
    long missingOut = 0, missingErr = 0;
    {
        // tokens appear in order; verify by scanning increasing expectations
        size_t pos = 0;
        for (long i = 1; i <= nOut; ++i) {
            std::string tok = "OUTLINE-" + std::to_string(i) + "\n";
            size_t p = captured.find(tok, pos);
            if (p == std::string::npos) { missingOut++; }
            else pos = p + tok.size();
        }
        pos = 0;
        for (long i = 1; i <= nErr; ++i) {
            std::string tok = "ERRLINE-" + std::to_string(i) + "\n";
            size_t p = captured.find(tok, pos);
            if (p == std::string::npos) { missingErr++; }
            else pos = p + tok.size();
        }
    }
    // 2. nothing else was written: strip all writer tokens, remainder must be empty
    std::string residual = captured;
    {
        std::string out;
        size_t i = 0;
        while (i < residual.size()) {
            if (residual.compare(i, 8, "OUTLINE-") == 0 || residual.compare(i, 8, "ERRLINE-") == 0) {
                size_t nl = residual.find('\n', i);
                if (nl == std::string::npos) { out.append(residual, i, std::string::npos); break; }
                i = nl + 1;
            } else {
                out.push_back(residual[i++]);
            }
        }
        residual = out;
    }

    printf("writer: %ld stdout lines, %ld stderr lines; captured %zu bytes\n",
           nOut, nErr, captured.size());
    bool pass = true;
    if (missingOut || missingErr) {
        printf("[FAIL] E1: writer bytes swallowed: missing OUT=%ld ERR=%ld\n", missingOut, missingErr);
        pass = false;
    }
    if (!residual.empty()) {
        printf("[FAIL] E1: library wrote %zu bytes to stdout/stderr:\n---\n%.2000s\n---\n",
               residual.size(), residual.c_str());
        pass = false;
    }
    // 3. script output went to messages
    bool msgsOk = messages_seen.size() >= 2 &&
                  messages_seen[0].find("scidb-mated-game") != std::string::npos &&
                  messages_seen[1].find("scidb-comment-text") == std::string::npos; // comment goes to pgn, not stdout
    bool persistOk = messages_seen.size() >= 3 &&
                     messages_seen[2].find("NGames") != std::string::npos;
    if (!msgsOk) { printf("[FAIL] E1: message-filter output not in messages: [%.300s]\n", messages_seen[0].c_str()); pass = false; }
    if (!persistOk && messages_seen.size() >= 3) { printf("[FAIL] E1: persistent output not in messages: [%.300s]\n", messages_seen[2].c_str()); pass = false; }
    (void)ok;
    printf(pass ? "[PASS] E1: stdout/stderr untouched by library, host output intact, script output captured\n"
                : "[FAIL] E1\n");
    return pass ? 0 : 1;
}
