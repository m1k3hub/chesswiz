// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
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

#if defined(__unix__) || defined(_WIN32)
# include <stdio.h>
#else
# include "m_stdio_internal.h"
#endif // __unix__


#if defined(IO_NO_THREADS) && !defined(_WIN32)

# ifdef getc
#  undef getc
# endif
# ifdef getchar
#  undef getchar
# endif
# ifdef putc
#  undef putc
# endif
# ifdef putchar
#  undef putchar
# endif

# define feof		feof_unlocked
# define ferror	ferror_unlocked
# define fflush	fflush_unlocked
# define fgetc		fgetc_unlocked
# define fgets		fgets_unlocked
# define fileno	fileno_unlocked
# define fputc		fputc_unlocked
# define fputs		fputs_unlocked
# define fread		fread_unlocked
# define fwrite	fwrite_unlocked
# define getc		getc_unlocked
# define getchar	getchar_unlocked
# define putc		putc_unlocked
# define putchar	putchar_unlocked

#endif

#if defined(_WIN32) && !defined(_mstl_windows_stdio_included)
# define _mstl_windows_stdio_included
# include <io.h>
# define flockfile _lock_file
# define funlockfile _unlock_file
# define fread_unlocked fread
# define fwrite_unlocked fwrite
# define fseeko _fseeki64
# define ftello _ftelli64

# include <stdint.h>
# include <stdlib.h>
# include <errno.h>
# include <string.h>

// MinGW has no POSIX delimiter reader.
inline ssize_t getdelim(char** data, size_t* capacity, int delimiter, FILE* fp)
{
	size_t size = 0;
	int ch;
	while ((ch = ::fgetc(fp)) != EOF)
	{
		if (size + 1 >= *capacity)
		{
			size_t next = *capacity ? 2*(*capacity) : 128;
			char* buffer = static_cast<char*>(::realloc(*data, next));
			if (!buffer) { errno = ENOMEM; return -1; }
			*data = buffer;
			*capacity = next;
		}
		(*data)[size++] = char(ch);
		if (ch == delimiter) break;
	}
	if (!size) return -1;
	(*data)[size] = '\0';
	return ssize_t(size);
}

inline ssize_t getline(char** data, size_t* capacity, FILE* fp)
{
	return getdelim(data, capacity, '\n', fp);
}

// Callback-backed FILE streams need a Windows implementation.
struct cookie_io_functions_t
{
	ssize_t (*read)(void*, char*, size_t);
	ssize_t (*write)(void*, const char*, size_t);
	int (*seek)(void*, int64_t*, int);
	int (*close)(void*);
};

// Windows has no callback-backed FILE. A read-only stream is drained into a
// temporary file (deleted on fclose) on the caller's thread, so the
// callbacks may use Tcl; the close callback runs once the data is copied.
// Write streams are still unsupported.
inline FILE* fopencookie(void* cookie, const char* mode, cookie_io_functions_t io)
{
	if (::strchr(mode, 'r') && !::strchr(mode, '+') && !::strchr(mode, 'w') && io.read)
	{
		char* path = ::_tempnam(0, "cw");
		FILE* fp = path ? ::fopen(path, "w+bTD") : 0;
		::free(path);
		if (!fp)
			return 0;

		char buf[65536];
		ssize_t n;
		while ((n = io.read(cookie, buf, sizeof(buf))) > 0)
		{
			if (::fwrite(buf, 1, size_t(n), fp) != size_t(n))
			{
				n = -1;
				break;
			}
		}
		if (io.close)
			io.close(cookie);
		if (n < 0)
		{
			::fclose(fp);
			errno = EIO;
			return 0;
		}
		::rewind(fp);
		return fp;
	}

	static bool const logged = (::fputs("Chesswiz: callback-backed output streams are unavailable on Windows\n", stderr), true);
	(void)logged;
	errno = ENOSYS;
	return 0;
}
#endif

// vi:set ts=3 sw=3:
