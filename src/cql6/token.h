#pragma once
#include <string>
#include "abbreviations.h"
#include "capturetype.h"

class PieceLoc;
class SquareToken;
class PieceToken;

#ifdef CQL6_EMBEDDED // scidb: Task 3 §B — token object registry
#include "scidb_retain.h"
#endif

class Token {
public:
#ifdef CQL6_EMBEDDED // scidb: search owns heap allocations, including clones
  SCIDB_SEARCH_ALLOCATOR(Token)
  virtual ~Token() = default;
#endif
  static int CurrentLineNumber;
  static int CurrentColumnNumber;
  int lineNumber{CurrentLineNumber};
  int columnNumber{CurrentColumnNumber};
  bool followsBlankLine{false};
  string theTrueString;
  string getTrueString()const {return theTrueString;}
  void setTrueString(string s){theTrueString=s;}
  int theTrueStart{-1};
  int theTrueStop{-1};
  int getTrueStart()const{return theTrueStart;}
  int getTrueStop()const{return theTrueStop;}
  void setTrueStartStop(int,int,const string&buffer);
  void printLocation();
  string locationString()const;
  virtual string toString()const;
  virtual string thisclass()const{return "UnknownToken";}
  static void syncLocation(int line,int column);
  void setStart(int line,int col);
  virtual bool isLParenToken()const{return false;}
  virtual bool isRParenToken()const{return false;}
  virtual bool isLBracketToken()const{return false;}
  virtual bool isRBracketToken()const{return false;}
  virtual bool isLBraceToken()const{return false;}
  virtual bool isRBraceToken()const{return false;}
  virtual bool isPathToken()const{return false;}
  virtual bool isEndPathToken()const{return false;}
  virtual bool isStarToken()const{return false;}
  virtual bool isPlusToken()const{return false;}
  virtual bool isWildcardStarToken()const{return false;}
  virtual bool isWildcardPlusToken()const{return false;}
  virtual bool isLeftDelimiter()const{return false;}
  virtual bool isRightDelimiter()const{return false;}
  virtual bool isLeftMatchFor(const Token*)const{return false;}
  virtual bool isBracedPlusToken()const{return false;}
  virtual bool isBracedStarToken()const{return false;}
  virtual bool isDashConToken()const{return false;}
  virtual bool isBraceRepToken()const{return false;}
  virtual bool isWildcardToken()const;
  virtual bool isQuestionMarkToken()const{return false;}
  virtual bool isWhiteSpaceToken()const{return false;}
  virtual string colorizerClass()const {return "";}
};

class StringToken: public Token{
public:
  const string value;
  string getString(){return value;}
  StringToken(string x);
  string toString()const override;
  virtual string thisclass()const override{return "StringToken";}
  bool eq(string s);
  string colorizerClass()const override{return "s";}
};

class SpecialToken: public StringToken{
public:
  SpecialToken(string v) : StringToken(v){};
  virtual string thisclass()const override{return "SpecialToken";}
  bool theFollowsWhitespace{false};
  void setFollowsWhitespace(){theFollowsWhitespace=true;}
  bool followsWhitespace()const{return theFollowsWhitespace;}
  bool isLParenToken()const override{return value=="(";}
  bool isRParenToken()const override{return value==")";}
  bool isLBraceToken()const override{return value=="{";}
  bool isRBraceToken()const override{return value=="}";}
  bool isLBracketToken()const override{return value=="[";}
  bool isRBracketToken()const override{return value=="]";}
  bool isPlusToken()const override{return value=="+";}
  bool isStarToken()const override{return value=="*";}
  bool isBracedPlusToken()const override{return value=="{+}";}
  bool isBracedStarToken()const override{return value=="{*}";}
  bool isLeftDelimiter()const override;
  bool isRightDelimiter()const override;
  bool isLeftMatchFor(const Token*)const override;
  bool isQuestionMarkToken()const override{return value=="?";};
  string colorizerClass()const override;
};

class InputFileToken: public StringToken{
public:
  InputFileToken(string x): StringToken(x){}
  virtual string thisclass()const override{return "InputFileToken";}
  string colorizerClass()const override{return "s";}
};

class OutputFileToken: public StringToken{
public:
  OutputFileToken(string x): StringToken(x){}
  virtual string thisclass()const override{return "OutputFileToken";}
  string colorizerClass()const override{return "s";}
};

class NameToken: public StringToken{
public:
  NameToken(string x): StringToken(x){}
  virtual string thisclass()const override{return "NameToken";}
};

class QuotedStringToken: public StringToken{
public:
  QuotedStringToken(string x):StringToken(x){}
  virtual string thisclass()const override{return "QuotedStringToken";}
};

class GroupIndexToken: public Token{
public:
  int value;
  GroupIndexToken(int i){value=i;}
  string toString()const override;
  virtual string thisclass()const override{return "GroupIndexToken";}
};

class GroupNumberToken: public Token{
public:
  int value;
  GroupNumberToken(int i){value=i;}
  string toString()const override;
  virtual string thisclass()const override{return "GroupNumberToken";}
};
  
class BraceRepToken:public Token{
public:
  int min{-1};
  int max{-1};
  BraceRepToken(int m,int n);
  string toString() const override;
  string thisclass()const override{return "BraceRepToken";}
  bool isBraceRepToken()const override{return true;}
};

class IntToken: public Token{
public:
  int value;
  IntToken(int i){value=i;}
  string toString() const override;
  virtual string thisclass()const override{return "IntToken";}
};

class KeywordToken:public StringToken{
public:
  virtual string thisclass()const override{return "KeywordToken";}
  static bool isReserved(string s);
  KeywordToken(string v);
  bool isPathToken()const override{return value=="path";}
  string colorizerClass()const override;
};

class IdToken: public StringToken{
public:
  IdToken(string x): StringToken(x){}
  virtual string thisclass()const override{return "IdToken";}
  string colorizerClass()const override{return "identifier";}
};

  
class PieceToken: public Token{
public:
  char value{0};
  PieceToken(char v);
  string toString()const override;
  static PieceToken *create(char c);
  static bool isAllowed(char c);
  bool isA()const{return value=='A';}
  bool isa()const{return value=='a';}
  bool is_()const{return value=='_';}
  virtual string thisclass()const override{return "PieceToken";}
};

class PieceDesignatorToken:public Token{
public:
  //  PieceLoc* pieceloc{NULL};
  const vector<PieceToken*>pieces;
  const vector<SquareToken*> squares;
  PieceDesignatorToken(vector<PieceToken*>,vector<SquareToken*>);
  string toString()const override;
  virtual string thisclass()const override{return "PieceDesignatorToken";}
  bool hasAa_()const;
  bool hasA()const;
  bool hasa()const;
  bool hasAa()const;
  bool isAll()const; //for the square token
  bool isAa()const; //this is the piece token
  bool has_()const;
  string colorizerClass()const override{return "piecedesignator";}
};
typedef PieceDesignatorToken PDT;

class SquareToken: public Token{
public:
  int minfile;
  int maxfile;
  int minrank;
  int maxrank;
  bool isAllowed(int mif, int maf, int mir, int mar);
  SquareToken(int mif, int maf, int mir, int mar);
  string toString()const override;
  virtual string thisclass()const override{return "SquareToken";}
  bool isAll()const{return minfile==0&&maxfile==7&&minrank==0&&maxrank==7;}
};

class EndPathToken: public Token{
public:
  EndPathToken(int linenumber, int columnnumber);
  string thisclass()const override{return "EndPathToken";}
  bool isEndPathToken()const override{return true;}
};
  
class WildcardStarToken:public Token{
public:
  WildcardStarToken(int line, int column);
  string thisclass()const override{return "WildcardStar";}
  bool isWildcardStarToken()const override{return true;}
};

class WildcardPlusToken:public Token{
public:
  WildcardPlusToken(int line, int column);
  string thisclass()const override{return "WildcardPlus";}
  bool isWildcardPlusToken()const override{return true;}
};

class DashToken: public Token{
public:
  bool theIsLeftTie{false};
  bool theIsRightTie{false};
  CaptureType theCaptureType{CaptureType::None};
  CaptureType getCaptureType()const{return theCaptureType;}
  bool theIsConToken{false};
  void fixPrevious(Token*previoustoken);
  void fixNext(Token*nexttoken);
  DashToken(CaptureType);
  bool isCon()const{return theIsConToken;}
  bool isNonCon()const{return !theIsConToken;}
  void setIsCon(){theIsConToken=true;}
  bool isLeftTie()const{return theIsLeftTie;}
  bool isRightTie()const{return theIsRightTie;}
  string thisclass()const override{return "DashToken";}
  bool isCapture()const{return theCaptureType==CaptureType::Capture;}
  bool isNonCapture()const{return theCaptureType==CaptureType::NonCapture;}
  string toString() const override;
  string colorizerClass()const override{return "dash";}
};
  
class WhiteSpaceToken: public Token{
public:
  WhiteSpaceToken(bool hasblankline,bool hasnewline);
  bool theHasBlankLine{false};
  bool theHasNewline{false};
  bool hasBlankLine()const{return theHasBlankLine;}
  bool hasNewline()const{return theHasNewline;}
  bool isWhiteSpaceToken()const override{return true;}
  string thisclass()const override{return "WhiteSpaceToken";}
  string colorizerClass()const override{return "c";}
};

class LineCommentToken: public Token{
public: 
  string thisclass()const override{return "LineCommentToken";}
};

class EndLineCommentToken: public Token{
public: 
  string thisclass()const override{return "EndLineCommentToken";}
};

class PieceDeclarationToken: public Token{
public:
  string thisclass()const override{return "PieceDeclarationToken";}
  string colorizerClass()const override{return "piecedesignator";}
};
