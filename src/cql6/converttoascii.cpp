#include "converttoascii.h"
#include "lexer.h"
#include "cqlassert.h"
#include "util.h"
#include <fstream>
using std::ofstream;
string ConvertToAscii::convert(const string& cqlstring){
  Lexer lexer(cqlstring,true);
  vector<Token*>tokens;
  while(Token*token=lexer.nextToken())
    tokens.push_back(token);
  stringstream ret;
  bool endswithidchar=false; //whether the last token ended with a-zA-Z_0-9
  for(Token*token:tokens){
    string currentstr=convert(token);
    if(currentstr.empty())continue;
    if(endswithidchar&&lexer.word_constituent(currentstr.front()))
      ret<<' ';
    ret<<currentstr;
    endswithidchar=lexer.word_constituent(currentstr.back());
  }
  return ret.str();
}

string ConvertToAscii::convert(const Token*token){
  const SpecialToken*special=dynamic_cast<const SpecialToken*>(token);
  if(special)return convert(special);
  const KeywordToken*kt=dynamic_cast<const KeywordToken*>(token);
  if(kt)return convert(kt);
  const PieceDesignatorToken*pd=dynamic_cast<const PieceDesignatorToken*>(token);
  if(pd)return convert(pd);
  const PieceDeclarationToken*pdt=dynamic_cast<const PieceDeclarationToken*>(token);
  if(pdt)return "[Aa]";
  const DashToken*dash=dynamic_cast<const DashToken*>(token);
  if(dash)return convert(dash);
  const PieceToken*pt=dynamic_cast<const PieceToken*>(token);
  uassert(!pt,"CTU bad pt");
  const SquareToken*st=dynamic_cast<const SquareToken*>(token);
  uassert(!st,"CTU bad st");
  return token->getTrueString(); 
}

string ConvertToAscii::convert(const KeywordToken*keyword){
  string v=keyword->value;
  return fromSimpleString(v);
}

string ConvertToAscii::convert(const SpecialToken*special){
  string v=special->value;
  return fromSimpleString(v);
}
string ConvertToAscii::fromSimpleString(const string& source){
  return source;
}


string ConvertToAscii::convert(const DashToken*dash){
  if(dash->isCapture())
  return "[x]";
  else return "--";
}

string ConvertToAscii::convert(const PieceToken*piece){
  return piece->toString();
}

string ConvertToAscii::convert(const SquareToken*square){
  if (square->isAll())
    return ".";
  return square->toString();
}
string ConvertToAscii::convert(const vector<SquareToken*>&squares){
  uassert(squares.size(),"ConvertToAscii: no squares");
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
  

string ConvertToAscii::convert(const PieceDesignatorToken*pd){
  stringstream s;
  if(pd->hasAa_())
    s<<convert(pd->squares);
  else if(pd->hasAa()){
    s<<"[Aa]";
    if(!pd->isAll())
      s<<convert(pd->squares);
  }//pd->hasAa
  else{
    if (pd->pieces.size()>1)
      s<<'[';
    for(const PieceToken* piece:pd->pieces)
      s<<convert(piece);
    if (pd->pieces.size()>1)
      s<<']';

    if(!pd->isAll())
      s<<convert(pd->squares);
  }
  return s.str();
}

string ConvertToAscii::fromCqlFile(string filename){
  cout<<"Converting to ascii file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  int filesize=(int)(contents.size());
  cout<<"In conversion: read "<<filesize<<" bytes"<<endl;
  return convert(contents);
}

void ConvertToAscii::fromCqlFileToFile(string fromname, string toname){
  cout<<"Converting the file "<<fromname<<" to ascii: ";
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
  cout<<"fromCqlFileToFile: opening file for writing ascii: "<<toname<<endl;
  ofstream*streamp=new ofstream(toname);
  if(!streamp->good())
    eassert(false,"CqlFileToFile: could not open file for writing ascii: ",toname);
  *streamp<<result;
  eassert(streamp->good(),"fromCqlFileToFile: write of ascii failed to: ",toname);
  streamp->flush();
  eassert(streamp->good(),"fromCqlFileToFile: write flush failed to: ",toname);
  cout<<"wrote "<<result.size()<<" bytes to: "<<toname<<endl;
}  
  
