#include "lexer.h"
#include "cqlassert.h"
string Lexer::convertEchoString(string contents){
  Lexer lexer(contents,true);
  vector<Token*>tokens;
  while(Token*token=lexer.nextToken())
    tokens.push_back(token);
  stringstream ret;
  for(Token*token:tokens)
    ret<<token->getTrueString();
  return ret.str();
}

