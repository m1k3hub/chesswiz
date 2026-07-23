// ======================================================================
// CBV Archive Codec — ChessBase Volume container format
// ======================================================================
// Reads .cbv archives by extracting and decompressing sub-files to a
// temporary directory, then delegating to a cbh::Codec for parsing.
//
// The CBV container wraps ChessBase database files (.cbh, .cbg, etc.)
// with its own compression. Each sub-file's data is divided into blocks:
//   - u16 block_size
//   - u16 unknown
//   - block_size bytes: compressed data
// Each block starts with a 1-byte compression flag:
//   0x00 = raw (uncompressed)
//   0x01 = LZ77-compressed only
//   0x02 = Huffman-encoded only
//   0x03 = Huffman-encoded then LZ77-compressed
//
// Huffman blocks use a 256-entry code table (4-bit code length per entry,
// followed by length bits of code), then a big-endian u16 decompressed size,
// then the Huffman-encoded bit stream.
//
// LZ77 compression uses a 16-bit code mask: each bit indicates if the next
// item is a literal byte (0) or a coded reference (1). Coded references
// encode RLE runs and back-references.
//
// Based on reverse engineering and antoyo's uncbv Rust tool.
// ======================================================================

#include "cbv_codec.h"
#include "cbh_codec.h"

#include "db_database.h"
#include "db_exception.h"
#include "db_game_data.h"
#include "db_game_info.h"
#include "db_consumer.h"
#include "db_tag_set.h"

#include "u_misc.h"
#include "u_progress.h"
#include "u_byte_stream.h"

#include "sys_file.h"

#include "m_fstream.h"
#include "m_string.h"
#include "m_stdio.h"

#include <cstring>
#include <cstdlib>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <unistd.h>

using namespace db;
using namespace db::cbv;
using namespace util;
using namespace sys;

namespace {

uint16_t readU16(unsigned char const* p)
{
	return uint16_t(p[0]) | (uint16_t(p[1]) << 8);
}

uint32_t readU32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
	     | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}


// ======================================================================
// Huffman tree node
// ======================================================================

struct HuffmanNode
{
	HuffmanNode*	left;
	HuffmanNode*	right;
	unsigned		value;	// 0-255 if leaf, otherwise no value

	HuffmanNode() :left(nullptr), right(nullptr), value(256) {}

	bool isLeaf() const { return value < 256; }
};


// Build a Huffman tree from 256 (bit_length, code) entries.

HuffmanNode*
buildHuffmanTree(unsigned const (&bitLengths)[256], unsigned const (&codes)[256])
{
	HuffmanNode* root = new HuffmanNode();

	for (unsigned byteValue = 0; byteValue < 256; ++byteValue)
	{
		unsigned len = bitLengths[byteValue];

		if (len == 0)
			continue;

		unsigned code = codes[byteValue];
		HuffmanNode* node = root;

		for (unsigned i = 0; i < len; ++i)
		{
			unsigned bit = (code >> (len - 1 - i)) & 1;

			if (bit == 0)
			{
				if (!node->left)
					node->left = new HuffmanNode();
				node = node->left;
			}
			else
			{
				if (!node->right)
					node->right = new HuffmanNode();
				node = node->right;
			}
		}

		node->value = byteValue;
	}

	return root;
}


void
deleteHuffmanTree(HuffmanNode* node)
{
	if (!node)
		return;
	deleteHuffmanTree(node->left);
	deleteHuffmanTree(node->right);
	delete node;
}


// Read a bit from a byte array at the given bit position.
// Returns 0 if the position is past the end of the buffer (safe default for malformed data).
inline
unsigned
readBit(unsigned char const* data, uint64_t bitPos, uint64_t dataLen)
{
	uint64_t bytePos = bitPos / 8;
	if (bytePos >= dataLen)
		return 0;
	return (data[bytePos] >> (7 - (bitPos % 8))) & 1;
}


// ======================================================================
// Decompression functions
// ======================================================================

// Decode Huffman-encoded data.
// bitPos starts after the tree definition in the block data.
// Returns the decoded data.

mstl::string
decodeHuffman(unsigned char const* data, uint64_t bitPos, uint64_t dataLen, unsigned decompressedSize)
{
	// Read Huffman tree: 256 entries, each has 4-bit code length then length bits of code.
	unsigned bitLengths[256];
	unsigned codes[256];

	uint64_t pos = bitPos;

	for (unsigned i = 0; i < 256; ++i)
	{
		unsigned len = 0;

		for (unsigned b = 0; b < 4; ++b)
		{
			len = (len << 1) | readBit(data, pos, dataLen);
			++pos;
		}

		bitLengths[i] = len;

		unsigned code = 0;

		for (unsigned b = 0; b < len; ++b)
		{
			code = (code << 1) | readBit(data, pos, dataLen);
			++pos;
		}

		codes[i] = code;
	}

	HuffmanNode* tree = buildHuffmanTree(bitLengths, codes);

	mstl::string result;
	result.reserve(decompressedSize);

	while (result.size() < decompressedSize)
	{
		HuffmanNode* node = tree;

		while (!node->isLeaf())
		{
			unsigned bit = readBit(data, pos, dataLen);
			++pos;

			node = (bit == 0) ? node->left : node->right;
			if (!node)
				return mstl::string(); // malformed Huffman tree
		}

		result += char(node->value & 0xFF);
	}

	deleteHuffmanTree(tree);
	return result;
}


// Decompress LZ77-compressed data using ChessBase's scheme.
// The data is a sequence of 16-bit code masks followed by coded/literal bytes.

mstl::string
decompressLZ77(unsigned char const* data, unsigned dataLen)
{
	mstl::string result;
	result.reserve(dataLen * 2);

	unsigned pos = 0;

	while (pos + 2 <= dataLen)
	{
		// Read 16-bit code mask
		uint16_t codeMask = readU16(data + pos);
		pos += 2;

		for (unsigned bitIdx = 0; bitIdx < 16; ++bitIdx)
		{
			if (pos >= dataLen)
				goto done;

			bool coded = (codeMask & 0x8000) != 0;
			codeMask <<= 1;

			if (coded)
			{
				if (pos >= dataLen)
					goto done;

				unsigned currentByte = data[pos++];
				unsigned high = currentByte >> 4;
				unsigned low = currentByte & 0xF;

				if (high == 0)
				{
					// RLE: repeat next byte (low + 3) times
					if (pos >= dataLen)
						goto done;

					char byte = data[pos++];
					result.append(low + 3, byte);
				}
				else if (high == 1)
				{
					// Long RLE
					if (pos + 1 >= dataLen)
						goto done;

					unsigned size = low + (data[pos] << 4) + 0x13;
					++pos;
					char byte = data[pos++];

					result.append(size, byte);
				}
				else
				{
					// Back-reference
					unsigned offset = ((data[pos] << 4) + low + 3);
					++pos;

					unsigned size;

					if (high == 2)
					{
						if (pos >= dataLen)
							goto done;

						size = data[pos++] + 0x10;
					}
					else
					{
						size = high;
					}

					if (offset > result.size())
						goto done;

					unsigned start = result.size() - offset;

					// Copy byte-by-byte to handle overlapping references
					for (unsigned i = 0; i < size; ++i)
						result += result[start + i];
				}
			}
			else
			{
				// Literal byte
				result += char(data[pos++]);
			}
		}
	}

done:
	return result;
}


// Extract and decompress a single block.
// Returns the number of bytes consumed from the input.

unsigned
extractBlock(unsigned char const* blockData, unsigned remainingSize, mstl::ofstream& out)
{
	if (remainingSize < 4)
		return remainingSize;

	unsigned blockSize = readU16(blockData);
	/* unsigned unknown = readU16(blockData + 2); */

	if (4 + blockSize > remainingSize)
		return remainingSize;

	unsigned char const* data = blockData + 4;

	if (blockSize < 1)
	{
		// Empty block
		return 4 + blockSize;
	}

	unsigned compFlag = data[0];
	bool huffmanEncoded = (compFlag & 0x02) != 0;
	bool compressed = (compFlag & 0x01) != 0;

	data += 1; // skip compression flag
	unsigned dataLen = blockSize - 1;

	mstl::string result;

	if (huffmanEncoded)
	{
		// Read big-endian u16 decompressed size
		if (dataLen < 2)
			return 4 + blockSize;

		unsigned decompressedSize = (unsigned(data[0]) << 8) | data[1];

		// Decode Huffman: skip 2 bytes for decompressed_size, start at bit offset (2 + 2*8)*8 = 18
		// Wait, the bit stream starts right after the decompressed size bytes
		// The first 2 bytes are the decompressed_size (big-endian u16)
		// Then the tree definition starts at byte 2 of the data-after-flag
		result = decodeHuffman(data + 2, 0, dataLen - 2, decompressedSize);
	}
	else
	{
		// Not huffman: data is the raw bytes (may still be LZ-compressed)
		result.assign(reinterpret_cast<char const*>(data), dataLen);
	}

	if (compressed)
	{
		mstl::string temp = decompressLZ77(
			reinterpret_cast<unsigned char const*>(result.c_str()),
			result.size());
		result = temp;
	}

	out.write(result.c_str(), result.size());

	return 4 + blockSize;
}


// ======================================================================
// CBV archive extraction
// ======================================================================

mstl::string
extractCBV(mstl::string const& cbvPath, mstl::string const& outDir, Progress& progress)
{
	mstl::ifstream strm(cbvPath, mstl::ios_base::in | mstl::ios_base::binary);

	if (!strm)
		IO_RAISE(Archive, Open_Failed, "cannot open CBV archive '%s'", cbvPath.c_str());

	unsigned char hdr[8];

	if (!strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr)))
		IO_RAISE(Archive, Corrupted, "CBV header too short in '%s'", cbvPath.c_str());

	uint16_t headerSize		= readU16(hdr + 0);
	uint16_t numEntries		= readU16(hdr + 2);
	uint16_t entryRecordSize	= readU16(hdr + 4);
	uint16_t version			= readU16(hdr + 6);

	if (headerSize != 8)
		IO_RAISE(Archive, Corrupted, "unexpected CBV header size (%u) in '%s'", headerSize, cbvPath.c_str());

	if (entryRecordSize < 33 || entryRecordSize > 1024)
		IO_RAISE(Archive, Corrupted, "suspicious CBV entry record size (%u) in '%s'", entryRecordSize, cbvPath.c_str());

	if (numEntries == 0 || numEntries > 1000)
		IO_RAISE(Archive, Corrupted, "suspicious CBV entry count (%u) in '%s'", numEntries, cbvPath.c_str());

	(void)version;

	progress.start(numEntries);
	progress.message("extract-cbv");

	mstl::string extractedRoot;

	// Read the entire file into memory for block-based decompression
	strm.seekg(0, mstl::ios_base::end);
	uint64_t fileSize = strm.tellg();
	strm.seekg(0, mstl::ios_base::beg);

	unsigned char* fileData = new unsigned char[fileSize];

	if (!strm.read(reinterpret_cast<char*>(fileData), fileSize))
	{
		delete[] fileData;
		IO_RAISE(Archive, Corrupted, "cannot read CBV data from '%s'", cbvPath.c_str());
	}

	if (entryRecordSize < 140)
		IO_RAISE(Archive, Corrupted, "CBV entry record too small (%u) in '%s'", entryRecordSize, cbvPath.c_str());

	// File data is laid out sequentially immediately after the header and the
	// file-list section. Each member's payload occupies exactly its
	// compressed_size bytes, so we walk the members in order and advance a
	// cumulative data offset. This matches the layout used by antoyo/uncbv:
	// the member name is the leading non-zero run within the first 132 bytes
	// of the record, compressed_size is a little-endian i32 at offset 132, and
	// decompressed_size is a little-endian i32 at offset 136. The 33 trailing
	// bytes (offset 140..172) are per-file metadata, not a fixed magic; an
	// earlier version of this code checked a hardcoded 4-byte signature there,
	// which only matched one specific archive and caused every member of every
	// other archive to be silently skipped (e.g. all TWIC .cbv archives).
	uint64_t dataOffset = uint64_t(headerSize) + uint64_t(numEntries) * entryRecordSize;

	for (unsigned i = 0; i < numEntries; ++i)
	{
		progress.update(i);

		unsigned char const* recordBuf = fileData + headerSize + i * entryRecordSize;

		// Member name: leading non-zero bytes within the first 132 bytes.
		unsigned nameLen = 0;
		while (nameLen < 132 && nameLen < entryRecordSize && recordBuf[nameLen] != 0)
			++nameLen;

		mstl::string fname(reinterpret_cast<char const*>(recordBuf), nameLen);

		uint64_t storedSize       = readU32(recordBuf + 132); // compressed_size (le_i32)
		uint64_t decompressedSize = readU32(recordBuf + 136); // decompressed_size (le_i32)
		(void)decompressedSize; // block decompression is self-delimiting

		if (fname.empty() || storedSize == 0)
		{
			dataOffset += storedSize;
			continue;
		}

		if (dataOffset + storedSize > fileSize)
			IO_RAISE(Archive, Corrupted,
			         "CBV member '%s' extends past end of file in '%s'",
			         fname.c_str(), cbvPath.c_str());

		// compressed_size and decompressed_size at record offsets 132/136
		// are not needed for block-based extraction (and may overflow int32_t).

		mstl::string outPath(outDir);
		outPath += '/';
		outPath += fname;

		mstl::ofstream out(outPath, mstl::ios_base::out | mstl::ios_base::binary | mstl::ios_base::trunc);

		if (!out)
		{
			delete[] fileData;
			IO_RAISE(Archive, Write_Failed, "cannot create extracted file '%s'", outPath.c_str());
		}

		// Decompress block by block
		unsigned char const* fileDataStart = fileData + dataOffset;
		uint64_t pos = 0;

		while (pos < storedSize)
		{
			unsigned consumed = extractBlock(fileDataStart + pos, unsigned(storedSize - pos), out);

			if (consumed == 0)
				break;

			pos += consumed;
		}

		out.close();

		dataOffset += storedSize;

		if (fname.size() >= 4 && fname.substr(fname.size() - 4) == ".cbh")
			extractedRoot = outPath.substr(0, outPath.size() - 4);
	}

	delete[] fileData;

	progress.update(numEntries);

	if (extractedRoot.empty())
		IO_RAISE(Archive, Corrupted, "CBV archive does not contain a .cbh file: '%s'", cbvPath.c_str());

	return extractedRoot;
}


void
removeDirTree(mstl::string const& dirPath)
{
	DIR* dir = ::opendir(dirPath.c_str());

	if (!dir)
		return;

	struct dirent* entry;

	while ((entry = ::readdir(dir)) != nullptr)
	{
		if (::strcmp(entry->d_name, ".") == 0 || ::strcmp(entry->d_name, "..") == 0)
			continue;

		mstl::string path(dirPath);
		path += '/';
		path += entry->d_name;

		struct stat st;

		if (::lstat(path.c_str(), &st) == 0)
		{
			if (S_ISLNK(st.st_mode))
				continue;

			if (S_ISDIR(st.st_mode))
				removeDirTree(path);
			else
				::unlink(path.c_str());
		}
	}

	::closedir(dir);
	::rmdir(dirPath.c_str());
}

} // namespace anonymous


Codec::Codec()
	:m_innerCodec(nullptr)
{
}


Codec::~Codec() throw()
{
	delete m_innerCodec;
	cleanupTempDir();
}


bool Codec::isWritable() const					{ return false; }
bool Codec::encodingFailed() const				{ return m_innerCodec ? m_innerCodec->encodingFailed() : false; }
DatabaseCodec::Format Codec::format() const		{ return format::ChessBase; }

unsigned Codec::maxGameRecordLength() const		{ return m_innerCodec ? m_innerCodec->maxGameRecordLength() : 0; }
unsigned Codec::maxGameLength() const			{ return m_innerCodec ? m_innerCodec->maxGameLength() : 0; }
unsigned Codec::maxGameCount() const			{ return m_innerCodec ? m_innerCodec->maxGameCount() : 0; }
unsigned Codec::maxPlayerCount() const			{ return m_innerCodec ? m_innerCodec->maxPlayerCount() : 0; }
unsigned Codec::maxEventCount() const			{ return m_innerCodec ? m_innerCodec->maxEventCount() : 0; }
unsigned Codec::maxSiteCount() const			{ return m_innerCodec ? m_innerCodec->maxSiteCount() : 0; }
unsigned Codec::maxAnnotatorCount() const		{ return m_innerCodec ? m_innerCodec->maxAnnotatorCount() : 0; }
unsigned Codec::minYear() const					{ return m_innerCodec ? m_innerCodec->minYear() : 0; }
unsigned Codec::maxYear() const					{ return m_innerCodec ? m_innerCodec->maxYear() : 0; }
unsigned Codec::maxDescriptionLength() const	{ return m_innerCodec ? m_innerCodec->maxDescriptionLength() : 0; }

mstl::string const& Codec::defaultEncoding() const	{ return m_innerCodec ? m_innerCodec->defaultEncoding() : m_encoding; }
unsigned Codec::gameFlags() const				{ return m_innerCodec ? m_innerCodec->gameFlags() : 0; }

mstl::string const& Codec::extension() const	{ static mstl::string ext("cbv"); return ext; }
mstl::string const& Codec::encoding() const		{ return m_encoding; }

db::tag::TagSet
Codec::tagFilter(Section section, TagSet const& tags) const
{
	if (m_innerCodec)
		return m_innerCodec->tagFilter(section, tags);

	return db::tag::TagSet();
}


void Codec::doOpen(mstl::string const&) { M_ASSERT(!"cbv does not support in-memory open"); }
void Codec::doOpen(mstl::string const&, mstl::string const&) { M_ASSERT(!"cbv does not support in-memory open"); }


void
Codec::doOpen(	mstl::string const& rootname,
					mstl::string const& originalSuffix,
					mstl::string const& encoding,
					util::Progress& progress)
{
	M_ASSERT(originalSuffix == "cbv");

	mstl::string cbvPath(rootname + ".cbv");

	// Create a temporary directory for extraction
	char tmpTemplate[] = "/tmp/scidb-cbv-XXXXXX";
	char* tmpDir = ::mkdtemp(tmpTemplate);

	if (!tmpDir)
		IO_RAISE(Archive, Open_Failed, "cannot create temporary directory for CBV extraction");

	m_tempDir = tmpDir;

	// Extract the archive
	m_extractedRoot = extractCBV(cbvPath, m_tempDir, progress);

	// Create the inner cbh::Codec and open it directly.
	// We are a friend of cbh::Codec so we can call its protected doOpen().
	m_innerCodec = new cbh::Codec;

	try
	{
		// Set the inner codec's m_db to our own DatabaseContent
		// so that it populates our game list, namebases, etc.
		m_innerCodec->m_db = m_db;

		m_innerCodec->doOpen(m_extractedRoot, "cbh", encoding, progress);
	}
	catch (...)
	{
		delete m_innerCodec;
		m_innerCodec = nullptr;
		cleanupTempDir();
		throw;
	}

	m_encoding = m_innerCodec->encoding();
}


void Codec::reloadDescription(mstl::string const& rootname)
{
	if (m_innerCodec)
		m_innerCodec->reloadDescription(m_extractedRoot);
}


void
Codec::reloadNamebases(	mstl::string const& rootname,
								mstl::string const& originalSuffix,
								util::Progress& progress)
{
	if (m_innerCodec)
		m_innerCodec->reloadNamebases(m_extractedRoot, "cbh", progress);
}


void
Codec::close()
{
	if (m_innerCodec)
	{
		m_innerCodec->close();
		delete m_innerCodec;
		m_innerCodec = nullptr;
	}

	cleanupTempDir();
}


unsigned
Codec::doDecoding(	::util::BlockFileReader* reader,
							GameInfo const& info,
							uint16_t* line,
							unsigned length,
							Board& startBoard,
							bool useStartBoard)
{
	M_ASSERT(m_innerCodec);
	return m_innerCodec->decodeGame(reader, info, line, length, startBoard, useStartBoard);
}


void
Codec::doDecoding(GameData& data, GameInfo& info, unsigned gameIndex, mstl::string* encoding)
{
	M_ASSERT(m_innerCodec);
	m_innerCodec->decodeGame(data, info, gameIndex, encoding);
}


save::State
Codec::doDecoding(	db::Consumer& consumer,
						TagSet& tags,
						GameInfo const& info,
						unsigned gameIndex)
{
	M_ASSERT(m_innerCodec);
	return m_innerCodec->exportGame(consumer, tags, info, gameIndex);
}


void Codec::reset()
{
	if (m_innerCodec)
		m_innerCodec->reset();
}


void
Codec::setEncoding(mstl::string const& encoding)
{
	m_encoding = encoding;

	if (m_innerCodec)
		m_innerCodec->setEncoding(encoding);
}


bool
Codec::getAttributes(	mstl::string const& filename,
								int& numGames,
								db::type::ID& type,
								mstl::string* description)
{
	if (!isCBV(filename))
		return false;

	char tmpTemplate[] = "/tmp/scidb-cbv-attr-XXXXXX";
	char* tmpDir = ::mkdtemp(tmpTemplate);

	if (!tmpDir)
		return false;

	mstl::string tmpDirStr(tmpDir);
	bool result = false;

	try
	{
		Progress progress;
		mstl::string extractedRoot = extractCBV(filename, tmpDirStr, progress);

		mstl::string cbhPath(extractedRoot + ".cbh");
		result = cbh::Codec::getAttributes(cbhPath, numGames, type, description);
	}
	catch (...)
	{
		result = false;
	}

	removeDirTree(tmpDirStr);
	return result;
}


void Codec::getSuffixes(mstl::string const&, StringList& result)
{
	result.push_back("cbv");
}


bool
Codec::isCBV(mstl::string const& filename)
{
	mstl::ifstream strm(filename, mstl::ios_base::in | mstl::ios_base::binary);

	if (!strm)
		return false;

	unsigned char hdr[8];

	if (!strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr)))
		return false;

	uint16_t numEntries		= readU16(hdr + 2);
	uint16_t entryRecordSize	= readU16(hdr + 4);

	return	readU16(hdr + 0) == 8						&&
			numEntries > 0 && numEntries < 1000		&&
			entryRecordSize >= 33 && entryRecordSize < 1024 &&
			readU16(hdr + 6) >= 1 && readU16(hdr + 6) <= 10;
}


void
Codec::cleanupTempDir()
{
	if (!m_tempDir.empty())
	{
		removeDirTree(m_tempDir);
		m_tempDir.clear();
		m_extractedRoot.clear();
	}
}

// vi:set ts=3 sw=3: