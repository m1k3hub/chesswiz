#pragma once
#include "token.h"
#include "abbreviations.h"
class ConvertToUnicode{
public:
  static string convert(const string &cqlstring);
  static string convert(const SpecialToken*);
  static string convert(const PieceDesignatorToken*);
  static string convert(const PieceDeclarationToken*);
  static string convert(const Token*);
  static string convert(const DashToken*);
  static string fromCqlFile(string filename);
  static string fromSimpleString(const string& simple);
  static string convert(const PieceToken*);
  static string convert(const SquareToken*);
  static string convert(const vector<SquareToken*>&);
  static string convert(const KeywordToken*);
  static string pieceCharToString(char c);
  static int pieceCharToCode(char c);
  static void fromCqlFileToFile(string fromfilename,string tofilename);
};

  
