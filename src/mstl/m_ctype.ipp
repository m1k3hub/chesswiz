// ======================================================================
// Author : $Author$
// Version: $Revision: 1453 $
// Date   : $Date: 2017-12-11 09:27:52 -0500 (Mon, 11 Dec 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2018 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include <ctype.h>
#include <string.h>

namespace mstl {

inline bool is_space(char c)	{ return ::isspace(static_cast<unsigned char>(c)); }
inline bool is_digit(char c)	{ return ::isdigit(static_cast<unsigned char>(c)); }
inline bool is_alpha(char c)	{ return ::isalpha(static_cast<unsigned char>(c)); }
inline bool is_alnum(char c)	{ return ::isalnum(static_cast<unsigned char>(c)); }


inline
char const*
skip_spaces(char const* s)
{
	while (s && *s && is_space(*s))
		++s;
	return s;
}


inline
char const*
skip_non_spaces(char const* s)
{
	while (s && *s && !is_space(*s))
		++s;
	return s;
}


inline
char const*
skip_words(char const* s, unsigned n)
{
	while (n--)
	{
		while (s && *s && !is_space(*s))
			++s;

		s = skip_spaces(s);
	}

	return skip_spaces(s);
}


inline
bool
case_equal(char const* lhs, char const* rhs)
{
	if (!lhs || !rhs)
		return lhs == rhs;

#ifdef _WIN32
	return ::_stricmp(lhs, rhs) == 0;
#else
	return ::strcasecmp(lhs, rhs) == 0;
#endif
}


inline
bool
is_numeric(char const* s)
{
	if (!s || !*s)
		return false;

	if (*s == '-' || *s == '+')
		++s;

	char const* p = s;

	while (*s && is_digit(*s))
		++s;

	return s > p && *s == '\0';
}


inline
char const*
to_bool(bool value)
{
	return value ? "true" : "false";
}

} // namespace mstl

// vi:set ts=3 sw=3:
