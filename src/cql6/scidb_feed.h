#ifndef SCIDB_FEED_H
#define SCIDB_FEED_H

#include "cql6_api.h"
#include <mutex>
#include <atomic>

class Game;

class ScidbGameSource {
public:
    ScidbGameSource(cql6_next_fn next_fn, void* ctx, bool trusted = false, bool san = true, bool truncate = false)
        : m_next_fn(next_fn), m_ctx(ctx), m_stopped(false), trustedMoves(trusted), wantSan(san), truncateIllegal(truncate) {}

    // Serialized call to host callback to get the next game.
    // Returns true if a game was fetched, false if no more games or stopped.
    bool nextGame(int thread_id, cql6_game* g) {
        if (m_stopped.load(std::memory_order_relaxed)) {
            return false;
        }
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_stopped.load(std::memory_order_relaxed)) {
            return false;
        }
        int ret = m_next_fn(m_ctx, thread_id, g);
        return (ret != 0);
    }

    void stop() {
        m_stopped.store(true, std::memory_order_relaxed);
    }

    static bool populateGame(const cql6_game* src, Game* dest, bool trusted = false, bool san = true,
                             bool truncate = false, bool* truncated = nullptr);
    bool truncateIllegal;
    bool trustedMoves;
    bool wantSan;

private:
    cql6_next_fn m_next_fn;
    void* m_ctx;
    std::mutex m_mutex;
    std::atomic<bool> m_stopped;
};

#endif // SCIDB_FEED_H
