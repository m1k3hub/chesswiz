#include "node.h"
#include "tokens.h"
/*
This file has convenience helper functions for toplevel grammar entities, which
convert between grammar entites and Node* entities, e.g.

  match_set
  match_numeric
  match_numeric (which could be in nodematch)

This is so the main grammar can be in toplevel.cpp
*/

SetBase*Tokens::match_setparameter(){
  int x=save();
  Node*node=match_substring_x(); //modified in 9.301 from match_attack_x
  if(!node||!node->isSet()){
    restore(x);
    return NULL;
  }
  return node->asSet();
}

SetBase*Tokens::match_set(){
  int x=save();
  Node*node=match_mulop_x();
  if(!node||!node->isSet()){
    restore(x);
    return NULL;
  }
  return node->asSet();
}

/*return the left side of a possible ~~ arg, used only in
  match_whileregex()
*/

Node*Tokens::match_numeric(){
  int x=save();
  Node*node=match_relop_x();
  if(node&&node->isNumeric())
    return node;
  restore(x);
  return NULL;
}

Node*Tokens::match_sortable(){
  int x=save();
  Node*node=match_relop_x();
  if(node&&node->isSortable())
    return node;
  restore(x);
  return NULL;
}

/*match_string() is used where a string is expected but concatenation of the
 argument IS allowed, like in readfile or the right side of dictionary
 assignment
*/

Node*Tokens::match_string(){
  int x=save();
  Node*node=match_relop_x();
  if(node&&node->isString())
    return node;
  restore(x);
  return NULL;
}

/*match_string_simple() is for matching strings 
when we want to disallow concatenation or the
  + operator generally, such as the argument to int (only place really) */

Node*Tokens::match_string_simple(){
  int x=save();
  Node*node=match_addop_x();
  if(node&&node->isString())
    return node;
  restore(x);
  return NULL;
}

ComplementNode* Tokens::match_complementnode(){
  if(!match_special("~")) return NULL;
  Node*node=match_intersect_x();
  if(!node||!node->isSet())
    show_error("Could not get set for argument to '~'");
  SetBase*set=node->asSet();
  return new ComplementNode(set);
}


