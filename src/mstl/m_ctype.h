// ======================================================================
// Author : $Author$
// Version: $Revision: 1453 $
// Date   : $Date: 2017-12-11 09:27:52 -0500 (Mon, 11 Dec 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2018 Gregor Cramer
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _mstl_ctype_included
#define _mstl_ctype_included

#include "m_types.h"

namespace mstl {

inline bool is_space(char c);
inline bool is_digit(char c);
inline bool is_alpha(char c);
inline bool is_alnum(char c);

inline char const* skip_spaces(char const* s);
inline char const* skip_non_spaces(char const* s);
inline char const* skip_words(char const* s, unsigned n);

inline bool case_equal(char const* lhs, char const* rhs);
inline bool is_numeric(char const* s);
inline char const* to_bool(bool value);

} // namespace mstl

#include "m_ctype.ipp"

#endif // _mstl_ctype_included

// vi:set ts=3 sw=3:
