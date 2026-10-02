#pragma once
#include <string>
#include <stdexcept>

// scidb: C++ exception for CQL exit / assert failures
class CqlException : public std::runtime_error {
public:
    explicit CqlException(const std::string& msg) : std::runtime_error(msg) {}
};
