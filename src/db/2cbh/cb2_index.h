// Shared 2CBH index framing. Record zero is the only header record;
// records 1..count-1 are games, including in databases larger than 255 games.
#ifndef _db_cb2_index_included
#define _db_cb2_index_included

#include <stddef.h>
#include <stdint.h>
#include <limits.h>

namespace db { namespace cb2 {

struct IndexLayout
{
    unsigned recordSize;
    unsigned gameCount;
};

// headerSize is the number of bytes available at header, fileSize the whole
// file length. This also supports the lightweight database attributes probe.
inline bool readIndexLayout(unsigned char const* header, size_t headerSize,
                            uint64_t fileSize, IndexLayout& layout)
{
    if (headerSize < 24)
        return false;
    unsigned const stride = unsigned(header[10]) | (unsigned(header[11]) << 8);
    uint64_t count = 0;
    for (unsigned i = 0; i < 8; ++i)
        count |= uint64_t(header[16 + i]) << (8 * i);
    // Only the 192-byte record layout has been verified. Do not interpret
    // future versions with offsets belonging to this version.
    // The file uses a 64-bit count; the database API uses unsigned game IDs.
    // Divide the file size first so a corrupt count cannot overflow a product.
    if (stride != 192 || count == 0 || count - 1 > UINT_MAX
        || fileSize % stride != 0 || count != fileSize / stride)
        return false;
    layout.recordSize = stride;
    layout.gameCount = unsigned(count - 1);
    return true;
}

} }
#endif
