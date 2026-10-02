#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "pieceloopnode.h"
#include "squareloopnode.h"
  

/* this MUST precede match_piecedesignator!*/
SquareLoopNode* Tokens::match_symbolicsquareloop(){
  int x=save();
  bool forall=match_forall();
  string name=match_id();
  if(name.empty()){
    restore(x);
    return NULL;
  }
  if(!match_element()){
    restore(x);return NULL;
  }
  SetBase*domain=match_set();
  if(!domain&&match_dictionary()){
    restore(x);
    return NULL;
  }
  if(!domain&&!match_dictionary()){
    show_error("Expecting set filter (or dictionary) following element symbol in x element ....");
    restore(x);
    return NULL;
  }
  Variable*v=environment->find(name);
  if(!v)v=environment->createSquareVariable(name);
  uassert(v,"could not create v squareloop symbol");
  SquareVariable*tv=dynamic_cast<SquareVariable*>(v);
  if(!tv)
    show_error("existing variable is not a square variable: "s+name);
  Node*body=match_node();
  if(!body)
    show_error("missing body in square loop filter");
  return new SquareLoopNode(tv,domain,body,forall);
}

    
  
PieceLoopNode* Tokens::match_symbolicpieceloop(){
  int x=save();
  bool forall=match_forall();
  if(!match_symbolicpiecedeclaration()){
    restore(x);
    return NULL;
  }
  string name=match_id();
  if(name.empty())
    show_error("expected variable name following piece declaration. Possible internal error here.");
  if(!match_element()){
    restore(x);
    return NULL;
  }
  Variable*v=environment->find(name);
  if(!v) v=environment->createPieceIdVariable(name);
  uassert(v,"could not create v in pieceloop");
  if(!(v->isPieceId()))
     show_error("In parsing piece loop, the index variable "s
		+ v->name
		+ " is not a piece variable");
  PieceIdVariable*tv=dynamic_cast<PieceIdVariable*>(v);
  uassert(tv,"in symbolpiece bad cast");
  
  SetBase*domain=match_set();
  if(!domain)
    show_error("Expecting a set expression in piece index loop after element symbol");
  Node*body=match_node();
  if(!body)
    show_error("missing body in piece loop filter");
  return new PieceLoopNode(tv,domain,body,forall);
}

bool Tokens::match_symbolicpiecedeclaration(){
  if(dynamic_cast<PieceDeclarationToken*>(current())!=NULL){
    forward();
    return true;
  }
  return false;
}
  
  
