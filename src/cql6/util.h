#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <ctype.h>
#include <vector>
#include <algorithm>
#include "abbreviations.h"
#include "chesstypes.h"
#include "gfile.h"
#include "pgnparse.h"
#include "range.h"
#include "squaremask.h"
#include "direction.h"
#include "myvector.h"
#include "cqlassert.h"
#include "cqlexit.h"

class QGame;

void tab();
void indent();
void unindent();

//Filename functions (in filename.cpp)

bool filename_is_pgn(string filename);
bool filename_is_cql(string filename);
bool filename_is_cqo(string filename);
string filename_extension(string filename);
string filename_stem(string name);
string filename_trim_path_prefix(string name);
string filename_trim_last(string name, char c);
string filename_trim_extension(string name);

class util{
 public:
  static void printgame(FILE* stream,Game* game);
  static void my_dump_board(boardT board);
  static int squareShiftDirection(int sq, directionT direction);
  static bool directionCompatible(pieceT piecet, directionT direction);
  static bool directionDiagonal(directionT direction);
  static bool directionOrthogonal(directionT direction);
  static void printgame(Game*game);
  static string game_to_string(Game*game);
  static string qgame_to_string(QGame*qgame);
  static bool positiveIntValue(string s, int*val);
  static bool nonnegativeIntValue(string s, int*val);
  static string num_to_string(long long v);
  static string num_to_string(size_t v);
  static string squarestring(int file, int rank);
  static string downcase(const string & a);
  static bool intValue(const string& s, int *val);
  static bool readString(string*sourcep, const string pattern); 
  static bool readPositiveInt(string*sourcep, int * valp);
  static string replaceAll(string content, const string& from, const string& to);
  static string quotestring(const string&);
  static string string_from_filename(string filename);
  #include "util-template.h"
};
