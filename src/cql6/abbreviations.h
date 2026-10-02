#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <ostream>
#include <iostream>
#include <utility>
using std::vector;
using std::string;
using std::endl;
using std::stringstream;
#ifndef CQL6_EMBEDDED // scidb: in embedded library builds `cout` is redirected to the
using std::cout;      // message sink by scidb_sink.h (force-included with -include)
#endif
using std::pair;
using namespace std::string_literals;
