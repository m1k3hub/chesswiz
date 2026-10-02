#pragma once
#include "abbreviations.h"
#include "uchar-strings.h"
class UChar{
public:
  UChar (int v);
  UChar (string bytes);
  UChar(){} // an invalid character
  string errorMessage;
  int theValue{-1};
  bool isValid()const{return theValue>=0;}
  bool isInvalid()const{return theValue<0;}
  bool isAscii()const{return theValue>=0&&theValue<=127;}
  int getValue()const{return theValue;}
  void setValue(int v);
  int size()const;
  string toString()const;
  static int char2int(char c);
  static void echoFile(string filename);
  static void convertEchoFile(string filename);
  static UChar parse(string buff, int offset);
  static vector<UChar>parseChars(const string&);
  static void test();
  static void initialize();
  bool isPiece()const;
  char charFromPiece()const;
  static UChar makePieceFromChar(char c);
  bool isTimes()const;
  static UChar makeTimes();
  static void printChar(char c);
  bool operator==(const UChar &other)const{return theValue==other.theValue;}
  static UChar invalidUChar();
  string name()const;
  static int toUnicode(const string&);
  static string toAscii(const int v);
  bool isFigurine()const;
  string uname()const;
};
std::ostream& operator<<(std::ostream& os, const UChar&);

  
  
  
