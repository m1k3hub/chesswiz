#include <stdio.h>
#include "node.h"
#include <sstream>
using std::stringstream;
int Token::CurrentLineNumber{0};
int Token::CurrentColumnNumber{0};


      
string Token::locationString()const{
  char buffer[100];
  if(!followsBlankLine)
    sprintf(buffer,"{Line %d, Column %d}",lineNumber,columnNumber);
  else
    sprintf(buffer,"{Line %d, Column %d [blankprecedes]}",lineNumber,columnNumber);
  return string(buffer);
}

StringToken::StringToken(string c):value(c){
}

bool PieceToken::isAllowed(char c){
  static char* allowed="RNBQKPrnbqkpAa_";
  for (int i=0;i<strlen(allowed);++i)
    if (c==allowed[i])return true;
  return false;
}

PieceToken::PieceToken(char c){
  uassert(isAllowed(c),"ptpt c");
  value=c;
}

PieceToken* PieceToken::create(char c){
  if(isAllowed(c)) return new PieceToken(c);
  return NULL;
}

SquareToken::SquareToken(int mif, int maf, int mir, int mar){
  uassert(isAllowed(mif,maf,mir,mar),"Internal error: bad square arguments");
  minfile=mif;
  maxfile=maf;
  minrank=mir;
  maxrank=mar;
}

bool SquareToken::isAllowed(int mif, int maf, int mir, int mar){
  return file_valid(mif)&&
    file_valid(maf)&&
    rank_valid(mir)&&
    rank_valid(mar)&&
    mif<=maf&&
    mir<=mar;
}

bool StringToken::eq(string s){
  return value==s;
}


string SquareToken::toString()const{
  char mif=file_to_char(minfile);
  char maf=file_to_char(maxfile);
  char mir=rank_to_char(minrank);
  char mar=rank_to_char(maxrank);
  stringstream s;
  if(minfile==maxfile)s<<mif;
  else s<<mif<<'-'<<maf;
  if(minrank==maxrank) s<<mir;
  else s<<mir<<'-'<<mar;
  return s.str();
}

string StringToken::toString()const{
  return string("<")+thisclass()+": "+locationString()+" \"" +value+"\">";
}

void Token::setStart(int line, int col){
  uassert(line>=0&&col>=0,"Token::setStart: bad input");
  lineNumber=line;
  columnNumber=col;
}

string IntToken::toString()const{
  stringstream s;
  s<<"<"
   << thisclass()
   <<": "<<locationString()
   <<' '<<value
   <<'>';
  
  return s.str();
}

string GroupNumberToken::toString()const{
  stringstream s;
  s<<"<"
   << thisclass()
   <<": "<<locationString()
   <<' '<<value
   <<'>';
  
  return s.str();
}

string GroupIndexToken::toString()const{
  stringstream s;
  s<<"<"
   << thisclass()
   <<": "<<locationString()
   <<' '<<value
   <<'>';
  
  return s.str();
}

string PieceToken::toString()const{
  string ret;
  ret+=value;
  return ret;
}


PieceDesignatorToken::PieceDesignatorToken(vector<PieceToken*>ps,
					   vector<SquareToken*>ss)
:
  pieces(ps),
  squares(ss)
{uassert(ps.size()>0||squares.size()>0,"pdt inputs");}

string PieceDesignatorToken::toString()const{
  stringstream s;
  s<<"<"<<thisclass()<<' '<<locationString()<<" pieces: ";
  for(auto p : pieces) s<<p->toString();
  s<<" squares: ";
  for(auto sq : squares) s<<sq->toString();
  s<<">";
    return s.str();
}


void Token::syncLocation(int line, int column){
  uassert(line>0&&column>0,"syncLocation");
  CurrentLineNumber=line;
  CurrentColumnNumber=column;
}

void Token::setTrueStartStop(int start,int stop,const string&buff){
  theTrueStart=start;
  theTrueStop=stop;
  uassert(theTrueStart>=0&&theTrueStart<=theTrueStop,"setTrueStartTStop: args");
  int len=(int)(buff.size());
  uassert(theTrueStop<=len,"settsss bad stop");
  theTrueString=buff.substr(theTrueStart,theTrueStop-theTrueStart);
}
  
string Token::toString()const{
  stringstream s;
  s<<"<"<<thisclass()<<' '<<locationString();
  //  if(followsBlankLine)
  //    s<<"followsBlankLine";
  s<<'>';
  return s.str();
}

string DashToken::toString()const{
  string ret="<DashToken";
  if (isLeftTie()) ret+=" L";
  if (isRightTie()) ret+=" R";
  if(isCapture())ret+=" x";
  if(isCon())ret+=" con";
  ret+= " "+locationString()+">";
  return ret;
}

DashToken::DashToken(CaptureType cap):
  theCaptureType(cap)
{uassert(captureTypeValid(theCaptureType),"dt cap arg");
}



EndPathToken::EndPathToken(int line, int column){
  lineNumber=line;
  columnNumber=column;
  uassert(lineNumber>=0&&columnNumber>=0,"ept lc error");
}

WildcardStarToken::WildcardStarToken(int line, int column){
  lineNumber=line;
  columnNumber=column;
  uassert(lineNumber>=0&&columnNumber>=0,"est lc error");
}

WildcardPlusToken::WildcardPlusToken(int line, int column){
  lineNumber=line;
  columnNumber=column;
  uassert(lineNumber>=0&&columnNumber>=0,"ept lc error");
}

bool SpecialToken::isLeftDelimiter()const{
  return isLBraceToken()||
    isLParenToken()||
    isLBracketToken();
}

bool SpecialToken::isRightDelimiter()const{
  return isRBraceToken()||
    isRParenToken()||
    isRBracketToken();
}

bool SpecialToken::isLeftMatchFor(const Token*token)const{
  uassert(token,"stislmn");
  if(token->isRBraceToken()) return isLBraceToken();
  if(token->isRParenToken())return isLParenToken();
  if(token->isRBracketToken())return isLBracketToken();
  return false;
}

bool Token::isWildcardToken()const{
  return isWildcardPlusToken()||
    isWildcardStarToken()||
    isQuestionMarkToken()||
    isBraceRepToken();
}

BraceRepToken::BraceRepToken(int m, int n):min(m),max(n)
{
  uassert(min>=0&&max>=0&&min<=max,"BraceRepToken: unexpected parameters to braced repetition");
}

string BraceRepToken::toString()const{
  stringstream s;
  s<<"<BraceRepToken["<<min<<','<<max<<']';
  return s.str();
}
 

void DashToken::fixPrevious(Token*previoustoken){
  uassert(previoustoken,"dtfp arg");
  uassert(theIsLeftTie==false,"dtfp bad left");
  if(previoustoken->isWhiteSpaceToken())return;
  SpecialToken*special=dynamic_cast<SpecialToken*>(previoustoken);
  if(special){
    const string&prevname=special->value;
    char last=prevname.back();
    const string noleftstar {"({:+-*/><,~="};
    if(noleftstar.find(last)!=string::npos)
      return;
    if(prevname=="[element]"||
       prevname=="focus"||
       prevname=="currentposition"||
       prevname=="flip"||
       prevname=="flipcolor"||
       prevname=="|"||
       prevname=="&")
      return;
  }
  theIsLeftTie=true;
}

void DashToken::fixNext(Token*nexttoken){
  uassert(nexttoken,"dtfn arg");
  if(nexttoken->isWhiteSpaceToken())return;
  SpecialToken*special=dynamic_cast<SpecialToken*>(nexttoken);
  if(special){
    const string&nextname=special->value;
    char first=nextname.front();
    const string norightstar {"})*+?:"};
    if(norightstar.find(first)!=string::npos)
      return;
  }
  theIsRightTie=true;
}

WhiteSpaceToken::WhiteSpaceToken(bool hasblank,bool hasnewline)
    :theHasBlankLine(hasblank),theHasNewline(hasnewline){}

bool PieceDesignatorToken::hasAa_()const{
  return hasA()&&hasa()&&has_();
}

bool PieceDesignatorToken::hasAa()const{
  return hasA()&&hasa();
}

bool PieceDesignatorToken::isAa()const{
  return hasA()&&hasa()&&!has_()&&isAll();
}
    
bool PieceDesignatorToken::hasA()const{
  return std::count_if(pieces.begin(),
		       pieces.end(),
		       [](const PieceToken* p){return p->isA();});
}
bool PieceDesignatorToken::hasa()const{
  return std::count_if(pieces.begin(),
		       pieces.end(),
		       [](const PieceToken*p){return p->isa();});
}
bool PieceDesignatorToken::has_()const{
  return std::count_if(pieces.begin(),
			 pieces.end(),
			 [](const PieceToken*p){return p->is_();});
}

bool PieceDesignatorToken::isAll()const{
  return squares.size()==1&&squares.front()->isAll();
}

string KeywordToken::colorizerClass()const{
  if(value=="path"||
     value=="focus"||
     value=="currentposition"||
     value=="curpos")
    return "s";
  return "k";
}

string SpecialToken::colorizerClass()const{
  return "s";
}
	
