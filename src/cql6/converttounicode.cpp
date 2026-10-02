#include "converttounicode.h"
#include "lexer.h"
#include "cqlassert.h"
#include "util.h"
#include <fstream>
using std::ofstream;
string ConvertToUnicode::convert(const string& cqlstring){
  Lexer lexer(cqlstring,true);
  vector<Token*>tokens;
  while(Token*token=lexer.nextToken())
    tokens.push_back(token);
  stringstream ret;
  for(Token*token:tokens)
    ret<<convert(token);
  return ret.str();
}

string ConvertToUnicode::convert(const Token*token){
  const SpecialToken*special=dynamic_cast<const SpecialToken*>(token);
  if(special)return convert(special);
  const KeywordToken*kt=dynamic_cast<const KeywordToken*>(token);
  if(kt)return convert(kt);
  const PieceDesignatorToken*pd=dynamic_cast<const PieceDesignatorToken*>(token);
  if(pd)return convert(pd);
  const PieceDeclarationToken*pdt=dynamic_cast<const PieceDeclarationToken*>(token);
  if(pdt)return convert(pdt);
  const DashToken*dash=dynamic_cast<const DashToken*>(token);
  if(dash)return convert(dash);
  const PieceToken*pt=dynamic_cast<const PieceToken*>(token);
  uassert(!pt,"CTU bad pt");
  const SquareToken*st=dynamic_cast<const SquareToken*>(token);
  uassert(!st,"CTU bad st");
  return token->getTrueString(); 
}

string ConvertToUnicode::convert(const KeywordToken*keyword){
  string v=keyword->value;
  return fromSimpleString(v);
}

string ConvertToUnicode::convert(const SpecialToken*special){
  string v=special->value;
  return fromSimpleString(v);
}
string ConvertToUnicode::fromSimpleString(const string& source){
  if(source=="&=")
    return UnicodeIntersectionString+"=";
  if(source=="|=")
    return UnicodeUnionString+"=";
  for(const std::pair<string,int>& e:AsciiToUnicode)
    if(e.first==source){
      return UChar(e.second).toString();
    }
  return source;
}


string ConvertToUnicode::convert(const DashToken*dash){
  if(dash->isCapture())
    return UChar(UnicodeTimes).toString();
  return UnicodeDashString;
}

string ConvertToUnicode::convert(const PieceToken*piece){
  return pieceCharToString(piece->value);
}

string ConvertToUnicode::convert(const SquareToken*square){
  if (square->isAll())
    return UChar(UnicodeGrid).toString();
  return square->toString();
}
string ConvertToUnicode::convert(const vector<SquareToken*>&squares){
  uassert(squares.size(),"ConvertToUnicode: no squares");
  stringstream s;
  if(squares.size()>1)
    s<<'[';
  SquareToken* front=squares.front();
  for(SquareToken*square:squares){
    if(square!=front)s<<',';
    s<<square->toString();
  }
  if(squares.size()>1)
    s<<']';
  return s.str();
}

string ConvertToUnicode::convert(const PieceDeclarationToken*pdt){
  stringstream s;
  s<<UChar(UnicodePiece);
  return s.str();
}

string ConvertToUnicode::convert(const PieceDesignatorToken*pd){
  stringstream s;
  if(pd->hasAa_())
    s<<convert(pd->squares);
  else if(pd->hasAa()){
    s<<UChar(UnicodePiece);
    if(!pd->isAll())
      s<<convert(pd->squares);
  }//pd->hasAa
  else{
    for(const PieceToken* piece:pd->pieces)
      s<<convert(piece);
    if(!pd->isAll())
      s<<convert(pd->squares);
  }
  return s.str();
}

string ConvertToUnicode::pieceCharToString(char c){
  return UChar(pieceCharToCode(c)).toString();
}

int ConvertToUnicode::pieceCharToCode(char c){
  switch(c){
  case 'R': return (int)UnicodePieces::R;
  case 'N': return (int)UnicodePieces::N;
  case 'B': return (int)UnicodePieces::B;
  case 'Q': return (int)UnicodePieces::Q;
  case 'K': return (int)UnicodePieces::K;
  case 'P': return (int)UnicodePieces::P;
  case 'r': return (int)UnicodePieces::r;
  case 'n': return (int)UnicodePieces::n;
  case 'b': return (int)UnicodePieces::b;
  case 'q': return (int)UnicodePieces::q;
  case 'k': return (int)UnicodePieces::k;
  case 'p': return (int)UnicodePieces::p;
  case 'A': return UnicodeWhitePiece;
  case 'a': return UnicodeBlackPiece;
  case '_': return UnicodeEmptySquare;
  }
  uassert(false,"unknown piece type in convert to unicode");
  return 0;
}

string ConvertToUnicode::fromCqlFile(string filename){
  cout<<"Converting to Unicode file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  int filesize=(int)(contents.size());
  cout<<"In conversion: read "<<filesize<<" bytes"<<endl;
  return convert(contents);
}

void ConvertToUnicode::fromCqlFileToFile(string fromname, string toname){
  cout<<"Converting the file "<<fromname<<" to: ";
  if(toname.empty())
    cout<<"stdout";
  else
    cout<<toname;
  cout<<endl;
  string result=fromCqlFile(fromname);
  if(!filename_is_cql(toname)){
    uassert(toname.empty(),"expected a .cql file name as output to fromCqlFileToFile");
    cout<<result<<endl;
    return;
  }
  cout<<"fromCqlFileToFile: opening file for writing: "<<toname<<endl;
  ofstream*streamp=new ofstream(toname);
  if(!streamp->good())
    eassert(false,"CqlFileToFile: could not open file for writing: ",toname);
  *streamp<<result;
  eassert(streamp->good(),"fromCqlFileToFile: write failed to: ",toname);
  streamp->flush();
  eassert(streamp->good(),"fromCqlFileToFile: write flush failed to: ",toname);
  cout<<"wrote "<<result.size()<<" bytes to: "<<toname<<endl;
}
  
  
