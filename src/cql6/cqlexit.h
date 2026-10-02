#pragma once
#include <string>
using std::string;
void cql_exit();
void cql_exit(string message);
void cql_exit(int);
void cql_gui_exit(string message, int linenumber, int columnnumber);
