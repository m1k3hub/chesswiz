// scidb: Task 3 §A — file lockdown test.
//
// mode "normal" <pgn> <scratchdir>:
//   one script per filesystem construct of the language; each must fail at PARSE
//   time with the "not available when CQL runs inside Scidb" error, and the
//   scratch dir must stay empty. cql(input ... output ...) headers must stay
//   ignored (no file opened or created, search runs from the feed).
//
// mode "strace" <pgn> <scratchdir>:
//   same searches, but bracketed by two marker file opens so the strace gate
//   script can prove that NO openat/open/creat/unlink/rename/mkdir happens
//   during the searches themselves.
#include "feed_common.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <dirent.h>

static bool dirIsEmpty(const std::string& d) {
    DIR* dir = opendir(d.c_str());
    if (!dir) return false;
    bool empty = true;
    while (struct dirent* e = readdir(dir)) {
        if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) { empty = false; break; }
    }
    closedir(dir);
    return empty;
}

static int runSearch(const char* script, const Dataset& ds, cql6_result* res, char* err, size_t errlen,
                     int threads = 4, int want_pgn = 0, int variations = 0) {
    cql6_options opt;
    memset(&opt, 0, sizeof(opt));
    opt.threads = threads;
    opt.want_pgn = want_pgn;
    opt.variations = variations;
    FeedContext fc;
    fc.dataset = &ds;
    fc.next_idx = 0;
    return cql6_search(script, &opt, fc_feedNextGame, &fc, res, err, errlen);
}

int main(int argc, char** argv) {
    if (argc < 4) { std::cerr << "usage: filelock normal|strace <pgn> <scratchdir>\n"; return 2; }
    std::string mode = argv[1];
    std::string pgnPath = argv[2];
    std::string scratch = argv[3];

    Dataset ds;
    if (!fc_loadDataset(pgnPath, ds)) { std::cerr << "cannot load dataset\n"; return 2; }
    mkdir(scratch.c_str(), 0777);

    // --- constructs that must fail at parse time ---
    struct Ban { const char* name; std::string script; };
    std::vector<Ban> bans = {
        {"writefile",        "writefile(\"" + scratch + "/evil.cqo\" \"pwned\")"},
        {"writefile-expr",   "x=\"evil.cqo\"\nwritefile(x \"pwned\")"},
        {"readfile",         "s = readfile \"/etc/passwd\""},
        {"readfile-filter",  "readfile \"/etc/passwd\" ~~ \"root\""},
        {"readfile-nested",  "writefile(\"" + scratch + "/x.cql\" readfile \"/etc/passwd\")"},
        {"html-export-path", "readfile \"" + scratch + "/secret.pgn\""},
    };

    bool pass = true;
    auto checkScratch = [&](const char* where) {
        if (mode == "strace") return; // normal mode checks emptiness; strace mode must not open anything
        if (!dirIsEmpty(scratch)) {
            printf("[FAIL] A: scratch dir not empty after %s\n", where);
            pass = false;
        }
    };

    int markerfd1 = -1, markerfd2 = -1;
    if (mode == "strace") {
        // bracket the search phase with marker opens (the gate script whitelists exactly these two)
        markerfd1 = open((scratch + "/../marker_start").c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0666);
        if (markerfd1 >= 0) close(markerfd1);
    }

    for (auto& b : bans) {
        cql6_result res; char err[2048]; err[0] = 0;
        int rc = runSearch(b.script.c_str(), ds, &res, err, sizeof(err));
        bool banned = (rc != 0) && strstr(err, "not available when CQL runs inside Scidb") != nullptr;
        printf("  %-16s rc=%d banned=%d err=%.90s\n", b.name, rc, (int)banned, err);
        if (!banned) { printf("[FAIL] A: %s was not rejected at parse time\n", b.name); pass = false; }
        cql6_free_result(&res);
        checkScratch(b.name);
    }

    // --- headers with input/output must stay ignored (no file touched, search works) ---
    {
        cql6_result res; char err[2048]; err[0] = 0;
        std::string s = "cql(input /etc/passwd output " + scratch + "/out.pgn)\ncheck";
        int rc = runSearch(s.c_str(), ds, &res, err, sizeof(err));
        if (rc != 0 || res.ngames <= 0) {
            printf("[FAIL] A: cql(input/output) header search failed rc=%d err=%.120s\n", rc, err);
            pass = false;
        } else {
            printf("  header-ignored  rc=0 ngames=%ld nmatches=%d\n", res.ngames, res.nmatches);
        }
        cql6_free_result(&res);
        checkScratch("header-ignored");
    }
    {
        // nonexistent input file must NOT be an error (it is ignored)
        cql6_result res; char err[2048]; err[0] = 0;
        std::string s = "cql(input " + scratch + "/does_not_exist.pgn output " + scratch + "/nope.pgn)\nmate";
        int rc = runSearch(s.c_str(), ds, &res, err, sizeof(err));
        if (rc != 0) { printf("[FAIL] A: nonexistent input file caused error: %.120s\n", err); pass = false; }
        cql6_free_result(&res);
        checkScratch("nonexistent-input");
    }

    // --- ordinary searches that must not touch the filesystem either ---
    {
        const char* ordinary[] = {
            "mate",
            "sort \"material\" ([a]<=6)",
            "if initial\n persistent NGames += 1\ncheck",
            "――=Q",
            "echo(source target) { source: (Kg1 and Pf2 and Pg2 and Ph2) kg8 and pf7 and pg7 and ph7 }",
            "check and comment \"scidb-filelock-comment\"", "mate and message \"scidb-filelock-message\"",
            "persistent dictionary D\nunbind D\nD[1]=2\ninitial",
        };
        for (const char* s : ordinary) {
            cql6_result res; char err[2048]; err[0] = 0;
            int rc = runSearch(s, ds, &res, err, sizeof(err), 8, 1, 0);
            if (rc != 0) { printf("[FAIL] A: ordinary search failed: %.120s\n", err); pass = false; }
            cql6_free_result(&res);
        }
        // one variations search too
        cql6_result res; char err[2048]; err[0] = 0;
        int rc = runSearch("mate", ds, &res, err, sizeof(err), 8, 0, 1);
        if (rc != 0) { printf("[FAIL] A: variations search failed: %.120s\n", err); pass = false; }
        cql6_free_result(&res);
        checkScratch("ordinary");
        printf("  ordinary searches done\n");
    }

    if (mode == "strace") {
        markerfd2 = open((scratch + "/../marker_end").c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0666);
        if (markerfd2 >= 0) close(markerfd2);
    }

    if (mode == "normal") {
        printf(pass ? "[PASS] A: every file construct banned at parse time, scratch dir empty\n"
                    : "[FAIL] A: file lockdown\n");
    } else {
        printf(pass ? "[OK] strace phase completed\n" : "[FAIL] strace phase\n");
    }
    return pass ? 0 : 1;
}
