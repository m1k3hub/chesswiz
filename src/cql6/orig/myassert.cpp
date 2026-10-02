//////////////////////////////////////////////////////////////////////
//
//  FILE:       myassert.cpp
//              Function to handle failed ASSERTs
//
//  Part of:    Scid (Shane's Chess Information Database)
//  Version:    0.3
//
//  Notice:     Copyright (c) 1999  Shane Hudson.  All rights reserved.
//
//  Author:     Shane Hudson (sgh@users.sourceforge.net)
//
//////////////////////////////////////////////////////////////////////


#include <stdlib.h>
#include <stdio.h>
#include "myassert.h"

std::atomic<unsigned long> numAsserts{0}; // scidb: Task 3 §B (was int, then unsigned long; ASSERT runs on all worker threads)

#ifdef CQL6_EMBEDDED // scidb: throw CqlException instead of printing and aborting
#include "cqlexception.h"
void _MyAssert(char *filename, unsigned linenum)
{
    throw CqlException(std::string("Scid assertion failed: ") + filename + ":" + std::to_string(linenum));
}
#else
void _MyAssert(char *filename, unsigned linenum)
{
    fflush (NULL);  // Flush all buffers first.
    fprintf (stderr, "\nASSERT FAILED!!: %s, line %u\n", filename, linenum);
    fflush (stderr);
    abort ();
}
#endif

//////////////////////////////////////////////////////////////////////
//  EOF: myassert.cpp
//////////////////////////////////////////////////////////////////////

