// ======================================================================
// Scidb Test Suite - C++ Backend Smoke Tests
// Keeps a small set of backend headers and APIs compileable.
// ======================================================================

#include "db/db_common.h"
#include "sys/sys_utf8.h"
#include "mstl/m_string.h"

#include <iostream>

namespace {

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

    std::cout << "PASS: C++ backend smoke tests compiled and ran" << std::endl;
    return 0;
}
