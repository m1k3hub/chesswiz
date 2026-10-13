// Portable startup-cache encoding. All integers are explicit little endian;
// object identities are table indices, never process addresses.
#ifndef DB_STARTUP_CACHE_H
#define DB_STARTUP_CACHE_H

#include "m_string.h"
#include <vector>
#include <memory>
#include <stdexcept>
#include <stdint.h>
#include <cstring>
#include "u_crc.h"
#include <unordered_map>
#include <algorithm>

namespace db { namespace cache {

struct Invalid : std::runtime_error {
    Invalid() : std::runtime_error("invalid player cache") {}
};

struct Writer {
    std::vector<unsigned char> bytes;
    void u32(uint32_t n) {
        size_t pos=bytes.size(); bytes.resize(pos+4);
        unsigned char* p=bytes.data()+pos;
        p[0]=n & 255; p[1]=(n >> 8) & 255; p[2]=(n >> 16) & 255; p[3]=(n >> 24) & 255;
    }
    void u64(uint64_t n) { u32(uint32_t(n)); u32(uint32_t(n >> 32)); }
    void string(mstl::string const& s) {
        u32(s.size()); bytes.insert(bytes.end(), s.c_str(), s.c_str()+s.size());
    }
};

class Reader {
    std::vector<unsigned char> const& bytes;
    size_t pos;
public:
    explicit Reader(std::vector<unsigned char> const& b, size_t start=0) : bytes(b), pos(start) {
        if (start>bytes.size()) throw Invalid();
    }
    size_t remaining() const { return bytes.size()-pos; }
    uint32_t u32() {
        if (remaining()<4) throw Invalid();
        unsigned char const* p=bytes.data()+pos; pos+=4;
        return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
    }
    uint64_t u64() { uint64_t lo=u32(); return lo | (uint64_t(u32()) << 32); }
    unsigned bounded(unsigned max) { unsigned n=u32(); if (n>max) throw Invalid(); return n; }
    unsigned count(unsigned width=4) {
        unsigned n=bounded(5000000);
        if (n>remaining()/width) throw Invalid();
        return n;
    }
    mstl::string string() {
        unsigned n=bounded(1048576);
        if (n>remaining()) throw Invalid();
        if (n && std::memchr(&bytes[pos], 0, n)) throw Invalid();
        mstl::string s(n ? reinterpret_cast<char const*>(&bytes[pos]) : "", n);
        pos+=n; return s;
    }
    void finish() const { if (remaining()) throw Invalid(); }
};

template<class T> struct Ids {
    std::unordered_map<T const*, unsigned> values;
    void add(T const* p) { if (!values.count(p)) values[p]=values.size(); }
    unsigned operator()(T const* p) const {
        auto i=values.find(p); if (i==values.end()) throw Invalid(); return i->second;
    }
};

// Reserve bucket capacity for the desired number of entries, including the
// load factor. Avoid rehashing while restoring a serialized dictionary.
template<class H> void reserveEntries(H& h, unsigned n) {
    h.reserve(unsigned(n*(100.0/H::Load))+1);
}

template<class V> typename V::value_type reference(Reader& r, V const& objects) {
    unsigned n=r.u32(); if (n>=objects.size()) throw Invalid(); return objects[n];
}

template<class V> void writeStrings(Writer& w, V const& v) {
    w.u32(v.size()); for (auto const& s : v) w.string(s);
}
template<class V> void readStrings(Reader& r, V& v) {
    unsigned n=r.count(); v.reserve(n);
    while (n--) v.push_back(r.string());
}

template<class M, class I> void writeLookup(Writer& w, M const& m, I const& ids) {
    w.u32(m.size());
    for (auto const& row : m) { w.u32(ids(row.first)); w.string(row.second); }
}
template<class M, class V> void readLookup(Reader& r, M& m, V const& objects) {
    unsigned n=r.count(8); auto& rows=m.container(); rows.reserve(n);
    while (n--) {
        auto p=reference(r, objects); auto s=r.string();
        rows.push_back(typename M::value_type(p, s));
    }
    // mstl::map is a sorted vector. Build in bulk instead of quadratic insertion.
    rows.qsort(+[](typename M::value_type const* a, typename M::value_type const* b) {
        return a->first<b->first ? -1 : b->first<a->first ? 1 : 0;
    });
    for (unsigned i=1; i<rows.size(); ++i)
        if (rows[i-1].first==rows[i].first) throw Invalid();
}

// Staging states own every allocation until the entire envelope and both
// databases have passed validation. Commit only swaps existing containers.
struct State {
    virtual ~State() {}
    virtual void commit() noexcept = 0;
};

inline uint64_t checksum(std::vector<unsigned char> const& bytes, size_t n) {
    // zlib's optimized CRC avoids a per-byte C++ loop in debug builds. The
    // envelope is limited to 512 MiB, safely within zlib's uInt length domain.
    return ::util::crc::compute(0, bytes.data(), static_cast<unsigned>(n));
}

} }
#endif
