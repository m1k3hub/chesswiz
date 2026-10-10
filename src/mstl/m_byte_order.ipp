// ======================================================================
// $RCSfile: m_bit_functions.h,v $
// $Revision: 609 $
// $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// $Author: gregor $
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

// GCC/Clang builtins: portable to Windows and macOS, which lack <byteswap.h> and <endian.h>.

namespace mstl {
namespace bo {

inline int16_t  swap(int16_t  v) { return __builtin_bswap16(v); }
inline int32_t  swap(int32_t  v) { return __builtin_bswap32(v); }
inline int64_t  swap(int64_t  v) { return __builtin_bswap64(v); }
inline uint16_t swap(uint16_t v) { return __builtin_bswap16(v); }
inline uint32_t swap(uint32_t v) { return __builtin_bswap32(v); }
inline uint64_t swap(uint64_t v) { return __builtin_bswap64(v); }

#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__

inline int16_t  swapLE(int16_t  v) { return v; }
inline int32_t  swapLE(int32_t  v) { return v; }
inline int64_t  swapLE(int64_t  v) { return v; }
inline uint16_t swapLE(uint16_t v) { return v; }
inline uint32_t swapLE(uint32_t v) { return v; }
inline uint64_t swapLE(uint64_t v) { return v; }

inline int16_t  swapBE(int16_t  v) { return __builtin_bswap16(v); }
inline int32_t  swapBE(int32_t  v) { return __builtin_bswap32(v); }
inline int64_t  swapBE(int64_t  v) { return __builtin_bswap64(v); }
inline uint16_t swapBE(uint16_t v) { return __builtin_bswap16(v); }
inline uint32_t swapBE(uint32_t v) { return __builtin_bswap32(v); }
inline uint64_t swapBE(uint64_t v) { return __builtin_bswap64(v); }

#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__

inline int16_t  swapBE(int16_t  v) { return v; }
inline int32_t  swapBE(int32_t  v) { return v; }
inline int64_t  swapBE(int64_t  v) { return v; }
inline uint16_t swapBE(uint16_t v) { return v; }
inline uint32_t swapBE(uint32_t v) { return v; }
inline uint64_t swapBE(uint64_t v) { return v; }

inline int16_t  swapLE(int16_t  v) { return __builtin_bswap16(v); }
inline int32_t  swapLE(int32_t  v) { return __builtin_bswap32(v); }
inline int64_t  swapLE(int64_t  v) { return __builtin_bswap64(v); }
inline uint16_t swapLE(uint16_t v) { return __builtin_bswap16(v); }
inline uint32_t swapLE(uint32_t v) { return __builtin_bswap32(v); }
inline uint64_t swapLE(uint64_t v) { return __builtin_bswap64(v); }

#else

#error "Unsupported byte order (neither Big Endian nor Little Endian)"

#endif

} // namespace bo
} // namespace mstl

// vi:set ts=3 sw=3:
