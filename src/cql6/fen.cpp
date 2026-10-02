#include "tokens.h"
#include "node.h"
#include "token.h"
#include <cctype>
Node* Tokens::node_from_fen(const string& fen, string & message){
  uassert(fen.size(),"empty fen in node_from_fen()");
  message="";
  stringstream rstream; //holds string to be built
  rstream<<"false or {"; //this just makes sure the node is logical, not square
  stringstream messagestream; //for the error message;
  int file=0, rank=7; //the next character to be read
  int len=(int)(fen.size());
  int nextchar=0;
  for(;nextchar<len;++nextchar){
    if(rank==0&&file==8)break;
    char c=fen.at(nextchar);
    if(rank<0||file>8){messagestream<<"malformed fen";goto err;}
    if (c=='/'){
      if(file!=8||rank<=0)
	{messagestream<<"'/' character too soon in fen"; goto err;}
      rank--;
      file=0;
    }
    else if (PieceToken::isAllowed(c)||c=='.'){
      if(file>7){messagestream<<"rank too long in fen";goto err;}
      rstream<<' '<<c<<util::squarestring(file,rank);
      file++;
    }
    else if (isdigit(c)){
      int val=(int)(c-'0');
      if(!(val>=1&&val<=8))
	{messagestream<<"invalid digit in fen: "<<c;goto err;}
      for (int i=0;i<val;++i){
	if(file>7){messagestream<<"too many empty squares in rank: "<<rank;goto err;}
	rstream<<" _"<<util::squarestring(file,rank);
	++file;
      }
    }//isdigit(c)
    else
      {messagestream<<"invalid character in fen: "<<c;goto err;}
  }//while char c
  eassert(rank==0&&file==8,"could not parse fen");
  rstream<<'}';
  return Tokens::node_from_string(rstream.str());
  err:
  messagestream<<" at fen index: "<<nextchar<<" while reading fen: "<<fen;
    message=messagestream.str();
    return NULL;
}
  
