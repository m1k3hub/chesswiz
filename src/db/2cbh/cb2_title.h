// Game titles measured with CBase26's Save mask > Game Tag (run 10).
#ifndef _cb2_title_included
#define _cb2_title_included

#include "m_string.h"
#include "m_vector.h"
#include <stdint.h>
#include <stddef.h>

namespace db { namespace cb2 {

struct GameTitle
{
    GameTitle(): language(42) {}
    GameTitle(uint32_t lang, mstl::string const& value): language(lang), text(value) {}
    uint32_t language; // ChessBase language id: English 42, German 53.
    mstl::string text;
};
typedef mstl::vector<GameTitle> GameTitles;

inline uint32_t titleWord(unsigned char const* p)
{
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
        | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

// total excludes its own four bytes; free slots have an invalid count.
// Read into a temporary so malformed records never leave partial titles.
inline bool readGameTitles(unsigned char const* lid, size_t size,
                           unsigned slot, GameTitles& titles)
{
    size_t const off = 0xb8 + size_t(slot) * 0x108a + 0xe76;
    if (!lid || off > size || size - off < 8) return false;
    unsigned char const* p = lid + off;
    uint32_t total = titleWord(p), count = titleWord(p + 4);
    if (total < 4 || total > 528 || total > size - off - 4
        || count > (total - 4) / 8) return false;
    size_t pos = 8, end = size_t(total) + 4;
    GameTitles result;
    for (uint32_t i = 0; i < count; ++i)
    {
        if (end - pos < 8) return false;
        uint32_t lang = titleWord(p + pos), len = titleWord(p + pos + 4);
        pos += 8;
        if (len > end - pos) return false;
        result.push_back(GameTitle(lang, mstl::string(
            reinterpret_cast<char const*>(p + pos), len)));
        pos += len;
    }
    if (pos != end) return false;
    titles = result;
    return true;
}

inline void appendTitleWord(mstl::string& data, uint32_t word)
{
    for (unsigned i = 0; i < 4; ++i) data += char(word >> (8*i));
}

inline bool encodeGameTitles(GameTitles const& titles, mstl::string& data)
{
    size_t total = 4;
    for (unsigned i = 0; i < titles.size(); ++i)
    {
        if (titles[i].text.size() > 520 || total + 8 + titles[i].text.size() > 528)
            return false;
        total += 8 + titles[i].text.size();
    }
    data.clear();
    appendTitleWord(data, uint32_t(total));
    appendTitleWord(data, uint32_t(titles.size()));
    for (unsigned i = 0; i < titles.size(); ++i)
    {
        appendTitleWord(data, titles[i].language);
        appendTitleWord(data, uint32_t(titles[i].text.size()));
        data.append(titles[i].text);
    }
    return true;
}

} }
#endif
