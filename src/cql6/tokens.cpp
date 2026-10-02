#include "abbreviations.h"
#include "tokens.h"
#include "environment.h"
#include "lexer.h"
#include <sstream>

string Tokens::toString(){
  stringstream s;
  s<<"Tokens: Bottom: "<<bottom<<" size: "<<tokens.size()<<endl;
  for(int i=0;i<tokens.size();++i){
    s<<"Token "<<i<<" of "<<tokens.size();
    s<<tokens[i]->toString();
    s<<endl;
  }
  s<<endl;
  return s.str();
}

bool Tokens::eof(){
  return bottom==(int)tokens.size();
}

Token* Tokens::current(){
  if(eof())return NULL;
  return tokens[bottom];
}

void Tokens::forward(){
  uassert(!eof(),"t forward eof");
  ++bottom;
}

Tokens::Tokens(vector<Token*>ts, Environment*e):environment(e),tokens(ts){
  if(environment==NULL)
    environment=new Environment;
  for(auto s:tokens)
    {uassert (s!=NULL,"Tokens::Tokens: unexpected null Token");}
  bottom=0;
  //  unbalancedParensCheck(); // we no longer need this: done by the lexer
  //  insertWildcardTokens();
}
    

int Tokens::save(){
  return bottom;
}

void Tokens::restore(int x){
  uassert(x<=bottom&&x>=0,"internal stack error");
  bottom=x;
}

Node* Tokens::node_from_string(const string &description){
  if (CqlShowFromString)
    cout<<"\nnodeFromString called on argument:\n"<<description<<endl;
  vector<Token*> tokenvector=Lexer::lexStringNested(description);
  uassert(tokenvector.size(),"Lex failed in node_from_string");
  Tokens tokens(tokenvector,environment);
  Node*node=tokens.match_node();
  uassert(node,"node_from_string: could not parse: ",description);
  uassert(tokens.eof(),"node_from_string: Unexpected text at end of: ",description);  
  return node;
}

