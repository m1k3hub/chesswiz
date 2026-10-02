#pragma once
#include <vector>
#include <string>
#include "uchar.h"
using std::string;
using std::vector;

#include "token.h"

class Lexer{
 public:
  Token* nextToken();
  static vector<Token*>lexFile();
  Lexer(const string & input, bool sync);
  void syncLocation();
  static vector<Token*> lexString(string contents);
  static vector<Token*> lexStringNested(string contents);
  static vector<Token*> lexFile(string filename);
  void read_to_starslash();
  vector<Token*> lex();
  string readstring();
  static Token* makeToken(string val);
  Token* match_int();
  Token* match_keyword();
  Token* match_pieceloc();
  bool isReserved(string);
  string next_word();
  string next_filename();
  bool end_of_pd();
  Token* match_filenametoken();
  Token* match_piecedesignator();
  Token* match_pd_emptysquare();
  Token* match_pd_emptypiece();
  Token* match_pd_nonempty();
  vector<PieceToken*>match_piecespecifier();
  vector<SquareToken*>match_squarespecifier();
  vector<PieceToken*>match_simplepiecespecifier();
  vector<PieceToken*>match_compoundpiecespecifier();
  vector<SquareToken*>match_simplesquarespecifier();
  vector<SquareToken*>match_compoundsquarespecifier();
  bool match_files(int*min,int*max);
  bool match_filerange(int*min,int*max);
  bool match_ranks(int*min,int*max);
  bool match_file(int*min);
  bool match_rankrange(int*min,int*max);
  bool match_rank(int*min);
  Token* match_id();
  bool skipWhiteSpace();
  void skipWhiteSpace(bool&foundspace,bool&foundblankline); 
  bool word_start(char);
  bool word_constituent(char);
  bool word_boundary(char);
  string next_digits();
  Token* match_predefined();
  StringToken* match_result_string();
  char peek();
  char forward();
  int save();
  void restore(int);
  bool eof() const {return currentCharacter>=length();}
  int length()const {return (int)(theBuffer.length());}
  Token* match_special();
  Token* match_special_unicode();
  bool match_string(string);
  bool match_char(char);
  QuotedStringToken* match_quotedstringtoken();
  void show_error(string);
  int getCurrentLine();
  int getCurrentColumn();
  string locationString();
  Token* match_castle();
  Token* match_hhdbtoken();
  Token* match_groupnumber();
  BraceRepToken*match_bracereptoken();
  QuotedStringToken* match_special_string();
  DashToken* match_dashtoken();
  string match_entity_string();
  static string convertEchoString(string);
 private:
  int currentCharacter=0;
  string theBuffer;
  const bool syncThis;
  vector<int>lineNumbers; //linenumber after reading the i'th character
  vector<int>columnNumbers; // column after reading the i'th character
  static vector<Token*>fixPath(const vector<Token*>&);
  static bool atPathTopLevel(const vector<Token*>&);
  static string toString(const vector<Token*>&);
  string trailingWhiteSpace;
  UChar match_uchar();
  bool match_uvalue(int);
  WhiteSpaceToken*match_whitespacetoken();
  vector<Token*>fixWhiteSpace(const vector<Token*>&tokens);
  string trueString(Token*token);
  vector<PieceToken*>match_unicodepiecespecifier();
  char charFromUnicodePieceSpecifier(UChar);
  vector<PieceToken*>match_singleunicodepiecespecifier();
  LineCommentToken*match_linecommenttoken();
  bool peekslashslashslash();
  static void bomTrim(string&input);
  PieceDesignatorToken*match_pd_Aa_followed_by_id();
  PieceDeclarationToken*match_piecedeclarationtoken();
};
