// ======================================================================
// Author : $Author$
// Version: $Revision: 938 $
// Date   : $Date: 2013-09-16 17:44:49 -0400 (Mon, 16 Sep 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2012-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "m_bitfield.h"

# if !defined(__SIZEOF_INT128__) || !__GNUC_PREREQ(4,4)

__attribute__((init_priority(101)))
uint128_t const mstl::bitfield<uint128_t>::m_zero(0u);

__attribute__((init_priority(101)))
uint128_t const mstl::bitfield<uint128_t>::m_one(1u);

__attribute__((init_priority(101)))
uint128_t const mstl::bitfield<uint128_t>::m_inverse(~uint64_t(0), ~uint64_t(0));

#endif // no native 128-bit support

// vi:set ts=3 sw=3:
