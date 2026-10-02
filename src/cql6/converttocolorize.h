#pragma once
#include "token.h"
#include "abbreviations.h"
#include "uchar.h"
class ConvertToColorize{
 public:
  static string convert(const string &cqlstring);
  static string convert(const Token* token);
  static string convert();
  static string escape(const string& str);
  static string span(const string&style, const string&value);
  static string escapeClass(UChar uchar);
  static string escapeTitle(UChar uchar);
  static string escapeAscii(const string&s);
};

