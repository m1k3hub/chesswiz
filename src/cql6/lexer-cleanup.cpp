#include "lexer.h"
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <cctype>
#include <sstream>
#include "util.h"

/*Given an input vector of tokens:
   1. convert any token that followsBlankLine to the number of
EndPathTokens corresponding to the number of PathTokens preceding it without
intervening unclosed delimiters if at top level of path
   2. convert any + or * or {+} or {*} to the corresponding wildcardtoken, when the token
      arises after a path token followed by any number of unclosed left parens and no
      other unclosed tokens
   2.5 convert any DashToken to the corresponding DashCon Token
   2.6. make sure that legal and countmoves are not at the toplevel of path
   3. check for correct nesting of delimiters
   4. If token a path, push it onto delimiters
*/  
vector<Token*> Lexer::fixPath(const vector<Token*>& tokens){
  vector<Token*>delimiters; //stack of PathToken and left delimiters
  vector<Token*>ret;
  for(Token* token:tokens){
    int currentline=token->CurrentLineNumber; //for debugging messages
    int currentcolumn=token->CurrentColumnNumber;
    /*step 1: conversion of blankline*/
    if(token->isEndPathToken()){
      while(!delimiters.empty()&&delimiters.back()->isPathToken()){
	delimiters.pop_back();
	ret.push_back(new EndPathToken(currentline,currentcolumn));
      }
      continue;
    }//if token->isEndPathToken()
    /* step 2: conversion of + or * to corresponding wildcards*/
    if((token->isPlusToken()||token->isBracedPlusToken())&&atPathTopLevel(delimiters)){
      ret.push_back(new WildcardPlusToken(currentline,currentcolumn));
      continue; //do not copy the original token to ret here
    }
    
    if((token->isStarToken()||token->isBracedStarToken())&&atPathTopLevel(delimiters)){
      ret.push_back(new WildcardStarToken(currentline,currentcolumn));
      continue; //do not copy original token to ret here
    }

    //    step2.5
    DashToken*dashtoken=dynamic_cast<DashToken*>(token);
    if(dashtoken&&atPathTopLevel(delimiters)){
      DashToken* condash=new DashToken(*dashtoken);
      condash->setIsCon();
      ret.push_back(condash);
      continue;
    }

    // step 2.6
    KeywordToken*keywordtoken=dynamic_cast<KeywordToken*>(token);
    if(keywordtoken&&atPathTopLevel(delimiters)){
      string v=keywordtoken->value;
      if(v=="legal"||v=="countmoves")
	cql_exit("The "s
		 +v
		 +" keyword is not allowed at the top level of path here: \n"
		 +keywordtoken->toString()
		 +" because the following -- might be misinterpreted as a"
		 +" constituent and not a filter. Put braces around the "
		 + "appropriate filter, e.g.\n      {legal --}\n");
    }
    //step 3: check for nesting and manage the stack generally
    if(token->isLeftDelimiter())
      delimiters.push_back(token);
    else if (token->isRightDelimiter()){
      /* start by popping all the path tokens that might be contained in some broader nesting, like
          {path .. }
      */
      while(delimiters.size()&&delimiters.back()->isPathToken())
	delimiters.pop_back();
      /*we have popped off all the path tokens that are to be closed. Now check the delimiter*/
      if(delimiters.empty())
	cql_exit("Lexer error: unmatched right delimiter: "s+token->toString());
      Token*matcher=delimiters.back();
      if(!matcher->isLeftMatchFor(token))
	cql_exit("Lexer error: mismatched delimiters. Right delimiter: "s 
		 +token->toString()
		 +" does not correspond to preceding left delimiter: "
		 +matcher->toString()
		 );
      delimiters.pop_back();
    }//if token->isRightDelimiter
    if(token->isPathToken())
      delimiters.push_back(token);
    ret.push_back(token);
  } // for each token;
  //now pop all the outstanding paths to check for unclosed left delimiters
  while(delimiters.size()&&delimiters.back()->isPathToken())
    delimiters.pop_back();
  if(delimiters.size())
    cql_exit("The left delimiter: "s + delimiters.back()->toString()+" was never matched by a corresponding right delimiter. Unexpected end of file.");
  return ret;
}

/*True if the stack ends in a PathToken followed by 0 or more leftparentokens*/

bool Lexer::atPathTopLevel(const vector<Token*>&delimiters){
  if(delimiters.empty())return false;
  for(int current=(int)(delimiters.size())-1;current>=0;--current){
    Token*token=delimiters.at(current);
    if(token->isPathToken())return true;
    if(token->isLParenToken())continue;
    return false;
  }
  return false;
} 
       
string Lexer::toString(const vector<Token*>& tokens){
  stringstream s;
  s<<"[";
  for(int i=0;i<(int)(tokens.size());++i)
    s<<"Token# "<<i<<": "<<tokens[i]->toString()<<endl;
  s<<"]"<<endl;
  return s.str();
}
    


    
    
