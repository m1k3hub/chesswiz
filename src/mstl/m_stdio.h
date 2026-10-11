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

// One shared registry across translation units; callbacks run on the caller's thread.
struct mstl_cookie_file
{
	FILE* fp;
	void* cookie;
	cookie_io_functions_t io;
	int64_t offset;
	mstl_cookie_file* next;
};

inline mstl_cookie_file*& mstl_cookie_files()
{
	static mstl_cookie_file* head = 0;
	return head;
}

inline mstl_cookie_file* mstl_find_cookie(FILE* fp)
{
	for (mstl_cookie_file* entry = mstl_cookie_files(); entry; entry = entry->next)
		if (entry->fp == fp) return entry;
	return 0;
}

inline int mstl_fflush(FILE* fp)
{
	mstl_cookie_file* entry = mstl_find_cookie(fp);
	if (!entry) return ::fflush(fp);
	if (::fflush(fp) == EOF) return EOF;
	int64_t end = ::_ftelli64(fp);
	if (end < 0) return EOF;
	if (end < entry->offset) { errno = ESPIPE; return EOF; }
	if (::_fseeki64(fp, entry->offset, SEEK_SET)) return EOF;
	char buf[65536];
	int rc = 0;
	while (entry->offset < end)
	{
		size_t size = size_t(end - entry->offset > int64_t(sizeof(buf))
			? sizeof(buf) : end - entry->offset);
		if (::fread(buf, 1, size, fp) != size)
		{
			errno = EIO;
			rc = EOF;
			break;
		}
		ssize_t n = entry->io.write(entry->cookie, buf, size);
		if (n > 0 && size_t(n) <= size) entry->offset += n;
		if (n != ssize_t(size))
		{
			errno = EIO;
			rc = EOF;
			break;
		}
	}
	int saved = errno;
	if (::_fseeki64(fp, end, SEEK_SET)) return EOF;
	if (rc) errno = saved;
	return rc;
}

inline int mstl_fclose(FILE* fp)
{
	mstl_cookie_file* entry = mstl_find_cookie(fp);
	if (!entry) return ::fclose(fp);
	int rc = mstl_fflush(fp);
	int saved = errno;
	if (entry->io.close && entry->io.close(entry->cookie) != 0 && !rc)
	{
		rc = EOF;
		saved = errno;
	}
	mstl_cookie_file** link = &mstl_cookie_files();
	while (*link != entry) link = &(*link)->next;
	*link = entry->next;
	::free(entry);
	if (::fclose(fp) == EOF && !rc) return EOF;
	if (rc) errno = saved;
	return rc;
}

// Read cookies are drained at open; write cookies are drained at explicit flush/close.
inline FILE* fopencookie(void* cookie, const char* mode, cookie_io_functions_t io)
{
	bool writing = ::strchr(mode, 'w') || ::strchr(mode, '+') || ::strchr(mode, 'a');
	if ((writing && !io.write) || (!writing && (!::strchr(mode, 'r') || !io.read)))
	{
		errno = EINVAL;
		return 0;
	}
	char* path = ::_tempnam(0, "cw");
	FILE* fp = path ? ::fopen(path, "w+bTD") : 0;
	::free(path);
	if (!fp) return 0;
	if (writing)
	{
		mstl_cookie_file* entry = static_cast<mstl_cookie_file*>(::malloc(sizeof(mstl_cookie_file)));
		if (!entry)
		{
			::fclose(fp);
			errno = ENOMEM;
			return 0;
		}
		entry->fp = fp;
		entry->cookie = cookie;
		entry->io = io;
		entry->offset = 0;
		entry->next = mstl_cookie_files();
		mstl_cookie_files() = entry;
		return fp;
	}
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
	if (io.close) io.close(cookie);
	if (n < 0)
	{
		::fclose(fp);
		errno = EIO;
		return 0;
	}
	::rewind(fp);
	return fp;
}
#endif

#if !defined(_WIN32) && !defined(_mstl_stdio_wrappers_included)
# define _mstl_stdio_wrappers_included
inline int mstl_fflush(FILE* fp) { return ::fflush(fp); }
inline int mstl_fclose(FILE* fp) { return ::fclose(fp); }
#endif

// vi:set ts=3 sw=3:
