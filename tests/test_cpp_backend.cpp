// ======================================================================
// Scidb Test Suite - C++ Backend Smoke Tests
// Keeps a small set of backend headers and APIs compileable.
// ======================================================================

#include "db/db_common.h"
#include "sys/sys_utf8.h"
#include "mstl/m_string.h"

#include <iostream>

namespace {

// Regression: adjacency is distance == 1. A previous implementation
// returned distance > 1, which is the opposite of adjacency and broke
// the endgame draw recognition in db_guess.cpp (king controls a square).
bool check_is_adjacent()
{
    using db::sq::ID;

    struct Case { ID a; ID b; bool expected; };
    Case const cases[] = {
        { db::sq::a1, db::sq::b1, true  },   // orthogonal
        { db::sq::a1, db::sq::a2, true  },   // orthogonal
        { db::sq::a1, db::sq::b2, true  },   // diagonal
        { db::sq::h8, db::sq::g7, true  },   // diagonal
        { db::sq::a1, db::sq::a1, false },   // same square is not adjacent
        { db::sq::a1, db::sq::c1, false },   // two files away
        { db::sq::a1, db::sq::a3, false },   // two ranks away
        { db::sq::a1, db::sq::b3, false },   // knight-like
    };

    for (Case const& c : cases)
    {
        if (db::sq::isAdjacent(c.a, c.b) != c.expected)
        {
            std::cerr << "FAIL: isAdjacent(" << int(c.a) << ", " << int(c.b)
                      << ") expected " << c.expected << std::endl;
            return false;
        }
    }
    return true;
}

void smoke_utf8()
{
    mstl::string ascii("hello");
    mstl::string nearMatch("hullo");

    unsigned count = sys::utf8::countChars(ascii);
    unsigned distance = sys::utf8::levenshteinDistance(ascii, nearMatch);

    (void)count;
    (void)distance;
}

void smoke_variant()
{
    db::variant::Type normal = db::variant::Normal;
    db::variant::Type threeCheck = db::variant::ThreeCheck;

    bool isNormal = db::variant::isNormalChess(normal);
    bool isMain = db::variant::isMainVariant(threeCheck);
    bool is960 = db::variant::isChess960(db::variant::Standard);

    (void)isNormal;
    (void)isMain;
    (void)is960;
}

void smoke_string()
{
    mstl::string value("  Hello  ");
    value.trim();
    sys::utf8::toLower(value.data());
}

} // namespace

int main()
{
    smoke_utf8();
    smoke_variant();
    smoke_string();

    if (!check_is_adjacent())
    {
        std::cout << "FAIL: C++ backend tests" << std::endl;
        return 1;
    }

    std::cout << "PASS: C++ backend smoke tests compiled and ran" << std::endl;
    return 0;
}
