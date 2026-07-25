// ======================================================================
// Count cipher for ChessBase Chess960 CBH game decoding
// ======================================================================

#include "cbh_count_cipher.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace db {
namespace cbh {

CountCipher::Table* CountCipher::s_h0 = 0;
CountCipher::Table* CountCipher::s_g = 0;
bool CountCipher::s_loaded = false;


CountCipher::CountCipher()
{
}


uint32_t
CountCipher::makeKey(unsigned a, unsigned b, unsigned c)
{
	return (uint32_t(a) << 16) | (uint32_t(b) << 8) | uint32_t(c);
}


bool
CountCipher::load(mstl::string const& path)
{
	if (s_loaded)
		return true;
	if (!s_h0) s_h0 = new Table;
	if (!s_g) s_g = new Table;

	mstl::string fpath(path);
	if (fpath.empty())
		fpath = "src/count_cipher_universal.json";

	FILE* f = ::fopen(fpath.c_str(), "rb");
	if (!f)
		return false;

	// Read entire file into memory.
	::fseek(f, 0, SEEK_END);
	long sz = ::ftell(f);
	::fseek(f, 0, SEEK_SET);
	if (sz <= 0)
	{
		::fclose(f);
		return false;
	}

	char* buf = new char[sz + 1];
	long n = ::fread(buf, 1, sz, f);
	::fclose(f);
	buf[n] = '\0';

	// Minimal parser for our specific JSON format:
	//   "H0": { "a,b,c": v, ... }
	//   "g_count0": { "a": v, ... }
	//
	// We scan for keys and values line by line.

	enum Section { None, H0, G };
	Section section = None;

	char const* p = buf;
	char const* end = buf + n;

	auto skipWs = [&]() {
		while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r'))
			++p;
	};

	auto matchLit = [&](char const* lit) -> bool {
		size_t len = ::strlen(lit);
		if (p + len <= end && ::strncmp(p, lit, len) == 0)
		{
			p += len;
			return true;
		}
		return false;
	};

	skipWs();
	if (!matchLit("{"))
	{
		delete[] buf;
		return false;
	}

	while (p < end)
	{
		skipWs();
		if (matchLit("}"))
			break;  // end of top-level object
		if (!matchLit("\""))
		{
			++p;
			continue;
		}

		// Read key name
		char keyName[64];
		size_t klen = 0;
		while (p < end && *p != '"' && klen < sizeof(keyName) - 1)
			keyName[klen++] = *p++;
		keyName[klen] = '\0';
		if (p < end && *p == '"')
			++p;

		skipWs();
		if (!matchLit(":"))
		{
			++p;
			continue;
		}
		skipWs();

		if (::strcmp(keyName, "H0") == 0)
		{
			section = H0;
			// Expect '{'
			skipWs();
			matchLit("{");
		}
		else if (::strcmp(keyName, "g_count0") == 0)
		{
			section = G;
			skipWs();
			matchLit("{");
		}
		else
		{
			// Skip value -- could be string, number, object, or array.
			section = None;
			int depth = 0;
			while (p < end)
			{
				if (*p == '{' || *p == '[') { ++depth; ++p; }
				else if (*p == '}' || *p == ']') { if (depth == 0) break; --depth; ++p; }
				else if (*p == '"') { ++p; while (p < end && *p != '"') { if (*p == '\\') ++p; if (p < end) ++p; } if (p < end) ++p; }
				else if (*p == ',') { if (depth == 0) break; ++p; }
				else ++p;
			}
			continue;
		}

		// Parse entries in current section
		while (p < end)
		{
			skipWs();
			if (matchLit("}"))
			{
				section = None;
				break;
			}
			if (!matchLit("\""))
			{
				++p;
				continue;
			}

			// Read entry key (e.g. "22,124,124" or "124")
			char entryKey[32];
			size_t eklen = 0;
			while (p < end && *p != '"' && eklen < sizeof(entryKey) - 1)
				entryKey[eklen++] = *p++;
			entryKey[eklen] = '\0';
			if (p < end && *p == '"')
				++p;

			skipWs();
			matchLit(":");
			skipWs();

			// Read value (integer)
			long val = ::strtol(p, const_cast<char**>(&p), 10);

			if (section == H0)
			{
				// Parse "a,b,c"
				unsigned a = 0, b = 0, c = 0;
				char* tok = ::strtok(entryKey, ",");
				if (tok) a = unsigned(::atoi(tok));
				tok = ::strtok(0, ",");
				if (tok) b = unsigned(::atoi(tok));
				tok = ::strtok(0, ",");
				if (tok) c = unsigned(::atoi(tok));
				(*s_h0)[makeKey(a, b, c)] = unsigned(val);
			}
			else if (section == G)
			{
				unsigned a = unsigned(::atoi(entryKey));
				(*s_g)[makeKey(0, 0, a)] = unsigned(val);
			}

			skipWs();
			matchLit(",");
		}
	}

	delete[] buf;
	s_loaded = !s_h0->empty();

	return s_loaded;
}


bool
CountCipher::isLoaded() const
{
	return s_loaded;
}


unsigned
CountCipher::lookupH0(unsigned countPrev, unsigned lcPrev, unsigned lc) const
{
	Table::const_iterator it = s_h0->find(makeKey(countPrev, lcPrev, lc));
	if (it == s_h0->end())
		return 0xffff;
	return it->second;
}


unsigned
CountCipher::lookupG(unsigned lc) const
{
	Table::const_iterator it = s_g->find(makeKey(0, 0, lc));
	if (it == s_g->end())
		return 0xffff;
	return it->second;
}


unsigned
CountCipher::h0Size() const
{
	return s_h0->size();
}


unsigned
CountCipher::gSize() const
{
	return s_g->size();
}

} // namespace cbh
} // namespace db

// vi:set ts=3 sw=3:
