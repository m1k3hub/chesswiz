//////////////////////////////////////////////////////////////////////
//
//  FILE:       myassert.h
//              ASSERT statement macro
//
//  Part of:    Scid (Shane's Chess Information Database)
//  Version:    2.3
//
//  Notice:     Copyright (c) 2001  Shane Hudson.  All rights reserved.
//
//  Author:     Shane Hudson (sgh@users.sourceforge.net)
//
//////////////////////////////////////////////////////////////////////


//////////////////////////////////////////////////////////////////////
//  ASSERT MACRO

// ASSERT macro: asserts an expression. Differs from the standard
//    assert in that it does NOT print the expression (this is a waste,
//    if an assert fails you can go to the code to see why) and that
//    it MUST be a statement, not part of a larger expression.
//    Adapted from the book "Writing Solid Code".

#ifndef MYASSERT_H

// scidb: numAsserts used to be incremented by every ASSERT (not only failures) from
// every worker thread: ~79 million times for one search of 5538 games. All threads
// fought over that single cache line (CPU time per search grew 20x from 1 to 32
// threads), it was a data race (TSan) and it overflowed (UBSan). Nothing reads the
// count, so the increment is gone; the variable stays only so that existing
// references still link.
#include <atomic>
extern std::atomic<unsigned long> numAsserts;

#ifdef ASSERTIONS

    void _MyAssert(char *, unsigned);

    #define ASSERT(f)               \
        if (f)                      \
            {}                      \
        else                        \
            _MyAssert(__FILE__, __LINE__)

#else   // #ifndef ASSERTIONS

    #define ASSERT(f) 

#endif  // #ifdef ASSERTIONS

#endif  // #ifndef MYASSERT_H


//////////////////////////////////////////////////////////////////////
//  EOF:    myassert.h
//////////////////////////////////////////////////////////////////////

