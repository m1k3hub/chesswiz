#include "cql6_api.h"
#include "scidb_feed.h"
#include "scidb_sink.h" // scidb: per-search output sink (no fd redirection)
#include "scidb_lockdown.h" // scidb: per-search filesystem lockdown
#include "cqlglobals.h"
#include "cqlthread.h"
#include "cql.h"
#include "cqlexception.h"
#include "gamesortinfo.h"
#include "variable.h"
#include "environment.h"
#include "sortvariable.h"
#include "util.h"
#include "markboard.h"

#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <thread>
#include <mutex>
#include <memory>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <limits>
#include <unistd.h>
#include <fcntl.h>

extern const char* CqlVersion;
extern const char* CqlBuild;

static std::mutex g_api_search_mutex;

struct EmbeddedWorkerMatch {
    int script_index;
    int game_number;
    int first_ply;
    std::string pgn;
    std::vector<SortValue> sort_values;
};

static bool compareEmbeddedWorkerMatch(const EmbeddedWorkerMatch& a, const EmbeddedWorkerMatch& b) {
    if (a.script_index != b.script_index) return a.script_index < b.script_index;
    if (!a.sort_values.empty() && a.sort_values.size() == b.sort_values.size()) {
        int len = (int)a.sort_values.size();
        for (int i = 0; i < len; ++i) {
            if (b.sort_values[i] < a.sort_values[i]) return true;
            else if (a.sort_values[i] < b.sort_values[i]) return false;
        }
    }
    return a.game_number < b.game_number;
}

struct EmbeddedScript {
    std::vector<CqlNode*> nodes;
    bool variations;
    CommentLevel comment_level;
};

// Boards and moves are prepared once. Each script receives its own traversal
// view and annotation state; exported PGN must not alter the next script's input.
class PreparedGame {
    struct PositionView {
        QPos* position;
        std::vector<QPos*> children;
        std::vector<QMove*> moves;
        int index, last;
    };
    QGame* game;
    std::vector<QPos*> positions;
    std::vector<PositionView> views;
    TagSection tags;
    std::vector<std::pair<std::string,std::string>> extra_tags;
    bool pgn_changed{false};
public:
    explicit PreparedGame(QGame* qgame): game(qgame), positions(qgame->allQPos), tags(*qgame->getTagSection()) {
        for (QPos* position : positions)
            views.push_back({position,position->children,position->moves,position->index,position->lastDescendantIndex});
        for (unsigned i=0;i<game->game->GetNumExtraTags();++i) {
            tagT& tag=game->game->GetExtraTags()[i];
            extra_tags.emplace_back(tag.tag,tag.value);
        }
    }
    void markPgnChanged() { pgn_changed=true; }
    void select(bool variations) {
        // Restore the full view before resetting annotations or exporting PGN.
        for (const auto& view : views) {
            view.position->children=view.children; view.position->moves=view.moves;
            view.position->index=view.index; view.position->lastDescendantIndex=view.last;
        }
        game->allQPos=positions;
        if (pgn_changed) {
            MarkBoard::gameMoveToPly(game->game,0);
            game->game->SetMoveComment(game->root->originalComment.empty() ? nullptr : game->root->originalComment.c_str());
            std::vector<std::pair<QPos*,int>> stack{{game->root,0}};
            while (!stack.empty()) {
                auto& entry=stack.back();
                if (entry.second==entry.first->nChildren()) {
                    stack.pop_back();
                    if (!stack.empty()) MarkBoard::gameBackup(game->game);
                } else {
                    int child_index=entry.second++;
                    QPos* child=entry.first->children[child_index];
                    MarkBoard::move_to_child(game->game,child_index);
                    game->game->SetMoveComment(child->originalComment.empty() ? nullptr : child->originalComment.c_str());
                    stack.emplace_back(child,0);
                }
            }
            game->game->ClearExtraTags();
            for (const auto& tag : extra_tags) game->game->AddPgnTag(tag.first.c_str(),tag.second.c_str());
            pgn_changed=false;
        }
        game->getCommentStack()->clear();
        game->clearRegexHistory();
        game->thePathStatus=PathStatus();
        std::vector<TagEntry> restored_tags(tags.theEntries);
        game->getTagSection()->theEntries.swap(restored_tags);
        game->getTagSection()->isInitialized=tags.isInitialized;
        for (QPos* position : positions) {
            position->addedComments.clear(); position->identificationComment.clear();
            position->deleteOriginalComment=false;
        }
        game->searchVariations=variations;
        if (!variations) {
            game->allQPos.clear();
            for (QPos* position=game->root;position;) {
                game->allQPos.push_back(position);
                if (position->children.size()>1) position->children.resize(1);
                if (position->moves.size()>1) position->moves.resize(1);
                position=position->children.empty() ? nullptr : position->children[0];
            }
            int last=int(game->allQPos.size())-1;
            for (int i=0;i<=last;++i) {
                game->allQPos[i]->index=i; game->allQPos[i]->lastDescendantIndex=last;
            }
        }
    }
};

static void embedded_thread_worker(
    const std::vector<EmbeddedScript>* scripts,
    QGame* qgame,
    int thread_idx,
    int nthreads,
    size_t* ngames_out,
    std::vector<EmbeddedWorkerMatch>* matches_out,
    bool want_pgn,
    std::atomic<bool>* stop_flag,
    std::exception_ptr* exc_out,
    std::mutex* exc_mutex
) {
    try {
        int gameNumber = qgame->getGameNumber();
        bool prepare_variations=false;
        for (const auto& script : *scripts) prepare_variations=prepare_variations || script.variations;
        while (!stop_flag->load(std::memory_order_relaxed)) {
            qgame->searchVariations=prepare_variations;
            if (!qgame->parseNextGame()) break;
            *ngames_out += 1;
            gameNumber = qgame->getGameNumber();
            bool exhausted=true;
            for (const auto& script : *scripts) {
                Range* range=script.nodes[thread_idx]->gamenumberrange;
                if (!range || gameNumber<=range->getMax()) exhausted=false;
            }
            if (exhausted) break;
            std::unique_ptr<PreparedGame> prepared;
            if (scripts->size()>1) prepared.reset(new PreparedGame(qgame));
            for (size_t script_index=0;script_index<scripts->size();++script_index) {
            const auto& script=(*scripts)[script_index];
            CqlNode* cqlnode=script.nodes[thread_idx];
            Range* gamenumberrange=cqlnode->gamenumberrange;
            if (gamenumberrange && (gameNumber<gamenumberrange->getMin() || gameNumber>gamenumberrange->getMax())) continue;
            CqlCommentLevel=script.comment_level;
            if (prepared) prepared->select(script.variations);

            bool matched = cqlnode->match_game(qgame);
#ifdef CQL6_EMBEDDED
            if (CqlTestAssertHook) CqlTestAssertHook(gameNumber, thread_idx);
#endif
            cql_output_status(gameNumber, thread_idx, matched);
            if (matched) {
                cqlnode->setFirstComment(qgame);
                qgame->prepareComments();
                // Determine first_ply: mainline ply of the first position that got the match comment
                // -1 if only variation positions matched.
                // scidb: only count the per-position match comments (CqlMatchString), not the
                // "Game number" header comment which always sits at ply 0.
                CommentStack* cs = qgame->getCommentStack();
                int first_ply = -1;
                for (int ci = 0; ci < cs->size(); ++ci) {
                    CommentEntry& ce = cs->at(ci);
                    if (ce.qpos && ce.qpos->getDepth() == 0 &&
                        CqlMatchString && ce.message == CqlMatchString) {
                        int ply = ce.qpos->getPly();
                        if ((first_ply == -1 || ply < first_ply) && ce.qpos->matchCommentVisible(CqlMatchString)) {
                            first_ply = ply;
                        }
                    }
                }

                EmbeddedWorkerMatch ewm;
                ewm.script_index=int(script_index);
                ewm.game_number = gameNumber;
                ewm.first_ply = first_ply;

                if (want_pgn) {
                    qgame->mergeComments(true);
                    ewm.pgn = util::game_to_string(qgame->game);
                    if (prepared) prepared->markPgnChanged();
                }

                // Collect sort values if any sort variables exist
                for (SortVariable* var : *cqlnode->environment->getSortVariables()) {
                    SortDirection dir = cqlnode->environment->getSortDirection(var);
                    SortValueType vartype = var->getSortValueType();
                    SortValue sortvalue(vartype, dir);
                    var->assignSortValue(&sortvalue);
                    ewm.sort_values.push_back(sortvalue);
                }

                matches_out->push_back(std::move(ewm));
            }
            }
        }
    } catch (...) {
        stop_flag->store(true, std::memory_order_relaxed);
        std::lock_guard<std::mutex> lock(*exc_mutex);
        if (!*exc_out) {
            *exc_out = std::current_exception();
        }
    }
}

// scidb: the process-wide stdout/stderr dup2 redirect (OutputSilencer) was REMOVED.
// The embedded library never prints: every stdio/cout call in the library is redirected
// at compile time to the per-search sink in scidb_sink.{h,cpp} (force-included via -include).
// The host's fd 1/2 are never touched, so other threads' output is unaffected.

extern "C" {

const char* cql6_version(void) {
    static const std::string ver = std::string(CqlVersion) + " build " + CqlBuild;
    return ver.c_str();
}

void cql6_free_result(cql6_result* r) {
    if (!r) return;
    if (r->matches) {
        for (int i = 0; i < r->nmatches; ++i) {
            if (r->matches[i].pgn) {
                free(r->matches[i].pgn);
                r->matches[i].pgn = NULL;
            }
        }
        free(r->matches);
        r->matches = NULL;
    }
    r->nmatches = 0;
    if (r->messages) {
        free(r->messages);
        r->messages = NULL;
    }
}

int cql6_search(const char* script_text, const cql6_options* opt, cql6_next_fn next, void* ctx,
                 cql6_result* out, char* err, size_t errlen) {
    if (out) memset(out, 0, sizeof(*out));
    if (err && errlen > 0) err[0] = '\0';

    if (!script_text || !opt || !next || !out) {
        if (err && errlen > 0) {
            snprintf(err, errlen, "Invalid NULL argument passed to cql6_search");
        }
        return -1;
    }

    // Guard concurrency: Only one cql6_search at a time
    std::unique_lock<std::mutex> search_lock(g_api_search_mutex, std::try_to_lock);
    if (!search_lock.owns_lock()) {
        if (err && errlen > 0) {
            snprintf(err, errlen, "Concurrent cql6_search call detected; only one search allowed at a time");
        }
        return -1;
    }

    // scidb: start capturing whatever the library would print into the per-search sink
    scidb_sink::begin();

    // scidb: lock the filesystem for the whole search (parse + match): no construct and
    // no code path may open/read/write/create/rename/delete anything while this is set.
    ScidbSearchActive.store(true, std::memory_order_relaxed);
    struct LockdownGuard {
        ~LockdownGuard() { ScidbSearchActive.store(false, std::memory_order_relaxed); }
    } lockdown_guard;

    struct ParseObjectsGuard {
        ~ParseObjectsGuard() { scidb_release_search_objects(); }
    } parse_objects_guard;

    try {
        // Re-initialize all globals
        cql_initialize();

        // scidb: mirror the standalone program's defaults so matched positions get the
        // "CQL" annotation comment (needed for first_ply and want_pgn parity with ./cql).
        // A literal, not setCqlGlobal(): that allocates a std::string and hands out its
        // c_str(), which leaked on every search.
        CqlMatchString = "CQL";
        CqlMatchStringSet = true;

        // Configure options
        CqlSearchVariations = (opt->variations != 0);
        CqlShowOutput = false;
        CqlPgnStdout = false;
        CqlTestAssertHook = opt->test_hook;

        int requested_threads = opt->threads;
        if (requested_threads <= 0) {
            requested_threads = cql_compute_number_threads();
        }
        if (requested_threads < 1) requested_threads = 1;

        if (opt->additional_script_count<0 || opt->additional_script_count>1023 ||
            (opt->additional_script_count && !opt->additional_scripts))
            throw CqlException("Invalid additional script array");
        bool force_single_thread=false, search_variations=false;
        std::vector<EmbeddedScript> scripts;
        for (int script_index=0;script_index<=opt->additional_script_count;++script_index) {
            const char* text=script_index ? opt->additional_scripts[script_index-1] : script_text;
            if (!text) throw CqlException("NULL additional script");
            cqlglobals_initialize();
            CqlMatchString="CQL"; CqlMatchStringSet=true;
            CqlSearchVariations=opt->variations!=0;
            CqlShowOutput=false; CqlPgnStdout=false;
            bool single=false;
            auto nodes=generateCqlNodesFromString(text,requested_threads,&single);
            cqlcheckvalid(nodes);
            scripts.push_back({std::move(nodes),CqlSearchVariations,CqlCommentLevel});
            force_single_thread=force_single_thread || single;
            search_variations=search_variations || CqlSearchVariations;
        }
        int actual_threads=force_single_thread ? 1 : requested_threads;
        if (force_single_thread) for (auto& script : scripts) script.nodes.resize(1);
        CqlSearchVariations=search_variations;
        CqlTestAssertHook=opt->test_hook;
        if (opt->prepare_feed) opt->prepare_feed(ctx,search_variations ? 1 : 0);
        ScidbGameSource game_source(next, ctx, opt->trusted_moves != 0, !opt->trusted_moves || opt->want_pgn != 0,
                                   opt->truncate_illegal_moves!=0);

        struct DeleteGame {
            void operator()(QGame* game) const noexcept {
                if (game) { delete game->game; delete game; }
            }
        };
        std::vector<std::unique_ptr<QGame, DeleteGame>> qgames;
        for (int i = 0; i < actual_threads; ++i) {
            qgames.emplace_back(new QGame(&game_source, i, CqlSearchVariations));
            if (opt->lazy_features) {
                unsigned features = 0;
                for (const auto& script : scripts) for (Node* node : script.nodes[i]->descendants()) {
                    const std::string kind = node->thisclass();
                    if (kind == "CheckNode") features |= 1;
                    if (kind == "MateNode") features |= 2;
                    if (kind == "StalemateNode") features |= 4;
                }
                qgames.back()->stateFeatures = features;
            }
        }

        std::atomic<bool> stop_flag(false);
        std::exception_ptr worker_exception = nullptr;
        std::mutex worker_exc_mutex;

        std::vector<size_t> ngames_array(actual_threads, 0);
        std::vector<std::vector<EmbeddedWorkerMatch>> worker_matches(actual_threads);
        std::vector<std::thread> threads;
        threads.reserve(actual_threads - 1);
        // Join even when allocation/thread creation fails partway through startup.
        // This guard dies before the vectors referenced by the workers.
        struct JoinWorkers {
            std::vector<std::thread>& threads;
            std::atomic<bool>& stop;
            ~JoinWorkers() {
                stop.store(true);
                for (auto& thread : threads) if (thread.joinable()) thread.join();
                CqlRunningThreads = false;
            }
        } join_workers{threads, stop_flag};

        if (actual_threads > 1) {
            CqlRunningThreads = true;
        }

        for (int t = 1; t < actual_threads; ++t) {
            threads.emplace_back(
                embedded_thread_worker,
                &scripts,
                qgames[t].get(),
                t,
                actual_threads,
                &ngames_array[t],
                &worker_matches[t],
                (opt->want_pgn != 0),
                &stop_flag,
                &worker_exception,
                &worker_exc_mutex
            );
        }

        // Thread 0 executes
        embedded_thread_worker(
            &scripts,
            qgames[0].get(),
            0,
            actual_threads,
            &ngames_array[0],
            &worker_matches[0],
            (opt->want_pgn != 0),
            &stop_flag,
            &worker_exception,
            &worker_exc_mutex
        );

        for (auto& thread : threads) thread.join();
        CqlRunningThreads = false;

        // Check if any worker encountered an exception
        if (worker_exception) {
            std::rethrow_exception(worker_exception);
        }

        // Merge matches across threads
        std::vector<EmbeddedWorkerMatch> all_matches;
        size_t total_games = 0;
        long total_skipped = 0; // scidb: games rejected by the feed
        long total_truncated = 0;
        for (int t = 0; t < actual_threads; ++t) {
            total_games += ngames_array[t];
            total_skipped += qgames[t]->nSkippedGames;
            total_truncated += qgames[t]->nTruncatedGames;
            all_matches.insert(all_matches.end(),
                               std::make_move_iterator(worker_matches[t].begin()),
                               std::make_move_iterator(worker_matches[t].end()));
        }

        // scidb: a systemic feed problem (every supplied game rejected) is an error,
        // not a silent empty result.
        if (total_games == 0 && total_skipped > 0) {
            scidb_sink::end(); // scidb: stop capturing
            if (err && errlen > 0)
                snprintf(err, errlen,
                         "cql6_search: every supplied game (%ld) was rejected by the feed "
                         "(corrupt or illegal game data)", total_skipped);
            return -1;
        }

        // Sort matches
        std::stable_sort(all_matches.begin(), all_matches.end(), compareEmbeddedWorkerMatch);

        // Enforce max_matches if > 0
        if (opt->max_matches > 0) {
            std::vector<size_t> counts(scripts.size(),0);
            all_matches.erase(std::remove_if(all_matches.begin(),all_matches.end(),[&](const EmbeddedWorkerMatch& match) {
                return counts[match.script_index]++ >= size_t(opt->max_matches);
            }),all_matches.end());
        }

        // Fill out results
        if (all_matches.size()>size_t(std::numeric_limits<int>::max()))
            throw CqlException("Too many matches for the CQL result array");
        out->ngames = (long)total_games;
        out->nskipped = total_skipped;
        out->ntruncated = total_truncated;
        out->threads_used = actual_threads;
        out->nmatches = (int)all_matches.size();

        if (out->nmatches > 0) {
            out->matches = (cql6_match*)calloc(out->nmatches, sizeof(cql6_match));
            if (!out->matches) throw std::bad_alloc();
            for (int i = 0; i < out->nmatches; ++i) {
                out->matches[i].game_number = all_matches[i].game_number;
                out->matches[i].first_ply = all_matches[i].first_ply;
                out->matches[i].script_index = all_matches[i].script_index;
                if (opt->want_pgn && !all_matches[i].pgn.empty()) {
                    out->matches[i].pgn = strdup(all_matches[i].pgn.c_str());
                    if (!out->matches[i].pgn) throw std::bad_alloc();
                } else {
                    out->matches[i].pgn = NULL;
                }
            }
        } else {
            out->matches = NULL;
        }

        // Collect messages: what the script printed (captured sink output, e.g. `message`
        // filters) plus the persistent variables (like the standalone program prints).
        std::string messages_str = scidb_sink::end();
        for (size_t script_index=0;script_index<scripts.size();++script_index) {
        CqlNode* cqlnode=scripts[script_index].nodes[0];
        std::vector<Variable*> persistents = cqlnode->getPersistentVariables();
        for (auto v : persistents) {
            if (!cqlnode->isQuietPersistentVariable(v)) {
                if (!messages_str.empty()) messages_str += "\n";
                if (scripts.size()>1) messages_str += "script " + std::to_string(script_index) + " ";
                messages_str += v->name + ": " + v->persistentValueAsString();
            }
        }
        }

        if (!messages_str.empty()) {
            out->messages = strdup(messages_str.c_str());
            if (!out->messages) throw std::bad_alloc();
        } else {
            out->messages = NULL;
        }

        return 0;

    } catch (const std::exception& ex) {
        cql6_free_result(out);
        scidb_sink::end(); // scidb: stop capturing even on the error path
        if (err && errlen > 0) {
            snprintf(err, errlen, "%s", ex.what());
        }
        return -1;
    } catch (...) {
        cql6_free_result(out);
        scidb_sink::end(); // scidb: stop capturing even on the error path
        if (err && errlen > 0) {
            snprintf(err, errlen, "Unknown error during cql6_search");
        }
        return -1;
    }
}

} // extern "C"
