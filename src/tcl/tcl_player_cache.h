// Startup-only persisted player/site cache adapter. Tcl's filesystem layer
// provides portable Unicode paths, binary I/O and atomic rename.
#ifndef TCL_PLAYER_CACHE_H
#define TCL_PLAYER_CACHE_H
#include "db_player.h"
#include "db_site.h"
#include "db_startup_cache.h"
#include <tcl.h>
#include <errno.h>
#include <sys/stat.h>

namespace tcl { namespace startup_cache {
// The cache is a startup operation: never retain player/site pointers across it.
bool playerCacheRestored = false;
bool playerCacheFinalized = false;
std::vector<unsigned char> playerCacheSources;

struct CacheObject {
    Tcl_Obj* obj;
    explicit CacheObject(char const* s) : obj(Tcl_NewStringObj(s, -1)) { Tcl_IncrRefCount(obj); }
    ~CacheObject() { Tcl_DecrRefCount(obj); }
};
struct CacheChannel {
    Tcl_Interp* ti;
    Tcl_Channel channel;
    CacheChannel(Tcl_Interp* interp, Tcl_Obj* path, char const* mode) : ti(interp),
        channel(Tcl_FSOpenFileChannel(interp, path, mode, 0600)) {
        if (!channel) throw db::cache::Invalid();
        if (Tcl_SetChannelOption(ti, channel, "-translation", "binary") != TCL_OK ||
            Tcl_SetChannelOption(ti, channel, "-encoding", "binary") != TCL_OK) {
            Tcl_Close(ti, channel); channel=nullptr; throw db::cache::Invalid();
        }
    }
    ~CacheChannel() { if (channel) Tcl_Close(ti, channel); }
    void close() {
        auto c=channel; channel=nullptr;
        if (Tcl_Close(ti, c) != TCL_OK) throw db::cache::Invalid();
    }
};

// Absent optional sources are recorded too: creating the user's FIDE list
// must invalidate the shipped-list cache. Other stat errors disable caching.
db::cache::Writer cacheHeader(Tcl_Interp* ti, Tcl_Obj* sources)
{
    db::cache::Writer w;
    w.u32(0x43505743); // CWPC
    w.u32(1); // format version
    if (Tcl_EvalEx(ti, "::scidb::misc::buildInfo", -1, TCL_EVAL_GLOBAL) != TCL_OK)
        throw db::cache::Invalid();
    Tcl_Obj* info=Tcl_GetObjResult(ti);
    Tcl_IncrRefCount(info);
    for (auto field : {"version", "revision", "gitSha"}) {
        CacheObject key(field); Tcl_Obj* value=nullptr;
        if (Tcl_DictObjGet(ti, info, key.obj, &value) != TCL_OK || !value) {
            Tcl_DecrRefCount(info); throw db::cache::Invalid();
        }
        w.string(mstl::string(Tcl_GetString(value)));
    }
    Tcl_DecrRefCount(info);
    int count=0; Tcl_Obj** paths=nullptr;
    if (Tcl_ListObjGetElements(ti, sources, &count, &paths) != TCL_OK || count>128)
        throw db::cache::Invalid();
    w.u32(count);
    for (int i=0; i<count; ++i) {
        auto path=Tcl_FSGetNormalizedPath(ti, paths[i]);
        if (!path) throw db::cache::Invalid();
        w.string(mstl::string(Tcl_GetString(path)));
        std::unique_ptr<Tcl_StatBuf, void(*)(Tcl_StatBuf*)> st(Tcl_AllocStatBuf(),
            [](Tcl_StatBuf* p) { Tcl_Free(reinterpret_cast<char*>(p)); });
        if (Tcl_FSStat(path, st.get())==0) {
            if (!S_ISREG(Tcl_GetModeFromStat(st.get()))) throw db::cache::Invalid();
            w.u32(1); w.u64(Tcl_GetSizeFromStat(st.get())); w.u64(Tcl_GetModificationTimeFromStat(st.get()));
        } else {
            if (Tcl_GetErrno()!=ENOENT && Tcl_GetErrno()!=ENOTDIR) throw db::cache::Invalid();
            w.u32(0); w.u64(0); w.u64(0);
        }
    }
    return w;
}

bool readPlayerCache(Tcl_Interp* ti, Tcl_Obj* path, Tcl_Obj* sources)
{
    playerCacheSources.clear();
    auto expected=cacheHeader(ti, sources);
    // Bind a later cache-write to the sources observed BEFORE parsing.
    playerCacheSources=expected.bytes;
    std::unique_ptr<Tcl_StatBuf, void(*)(Tcl_StatBuf*)> st(Tcl_AllocStatBuf(),
        [](Tcl_StatBuf* p) { Tcl_Free(reinterpret_cast<char*>(p)); });
    if (Tcl_FSStat(path, st.get())!=0 || !S_ISREG(Tcl_GetModeFromStat(st.get())))
        throw db::cache::Invalid();
    uint64_t length=Tcl_GetSizeFromStat(st.get());
    if (length<expected.bytes.size()+8 || length>512u*1024u*1024u) return false;
    // Fill one pre-sized buffer directly. Repeated vector insertions copy
    // bytes individually in this project's unoptimized developer builds.
    std::vector<unsigned char> bytes(static_cast<size_t>(length));
    CacheChannel file(ti, path, "rb");
    size_t offset=0;
    while (offset<bytes.size()) {
        int n=Tcl_ReadRaw(file.channel, reinterpret_cast<char*>(bytes.data()+offset),
                          int(std::min<size_t>(65536, bytes.size()-offset)));
        if (n<=0) throw db::cache::Invalid();
        offset+=n;
    }
    char extra;
    if (Tcl_ReadRaw(file.channel, &extra, 1)!=0) throw db::cache::Invalid();
    file.close();
    if (bytes.size()<expected.bytes.size()+8 ||
        !std::equal(expected.bytes.begin(), expected.bytes.end(), bytes.begin())) return false;
    uint64_t saved=0;
    for (unsigned i=0; i<8; ++i) saved |= uint64_t(bytes[bytes.size()-8+i]) << (8*i);
    if (saved!=db::cache::checksum(bytes, bytes.size()-8)) return false;
    bytes.resize(bytes.size()-8);
    // Reader sees only the database payload. Validate both before any mutation.
    db::cache::Reader reader(bytes, expected.bytes.size());
    auto players=db::Player::readCache(reader);
    auto sites=db::Site::readCache(reader);
    reader.finish();
    if (cacheHeader(ti, sources).bytes!=expected.bytes) return false;
    players->commit(); sites->commit();
    playerCacheRestored=true; playerCacheFinalized=true;
    return true;
}

bool writePlayerCache(Tcl_Interp* ti, Tcl_Obj* path, Tcl_Obj* sources)
{
    if (!playerCacheFinalized || playerCacheSources.empty()) return false;
    auto w=cacheHeader(ti, sources);
    if (playerCacheSources!=w.bytes) return false;
    auto header=w.bytes;
    db::Player::writeCache(w); db::Site::writeCache(w);
    w.u64(db::cache::checksum(w.bytes, w.bytes.size()));
    if (w.bytes.size()>512u*1024u*1024u) return false;
    // EXCL avoids collisions and symlink following, including simultaneous starts.
    Tcl_Time now; Tcl_GetTime(&now);
    static unsigned serial=0;
    for (unsigned attempt=0; attempt<16; ++attempt) {
        mstl::string temp;
        temp.format("%s.%lld.%ld.%u.tmp", Tcl_GetString(path),
                    static_cast<long long>(now.sec), now.usec, ++serial);
        CacheObject tmp(temp.c_str());
        try {
            CacheChannel file(ti, tmp.obj, "WRONLY CREAT EXCL");
            try {
                size_t offset=0;
                while (offset<w.bytes.size()) {
                    int n=Tcl_WriteRaw(file.channel, reinterpret_cast<char const*>(&w.bytes[offset]),
                                    int(std::min<size_t>(65536, w.bytes.size()-offset)));
                    if (n<=0) throw db::cache::Invalid();
                    offset+=n;
                }
                file.close();
                if (cacheHeader(ti, sources).bytes!=header || Tcl_FSRenameFile(tmp.obj, path)!=0)
                    throw db::cache::Invalid();
                return true;
            } catch (...) {
                // Windows cannot delete an open file. Close before cleanup on
                // write/flush/rename failure as well as on the success path.
                if (file.channel) { try { file.close(); } catch (...) {} }
                Tcl_FSDeleteFile(tmp.obj); throw;
            }
        } catch (...) {
            if (Tcl_GetErrno()!=EEXIST) return false;
        }
    }
    return false;
}
} }

#endif
