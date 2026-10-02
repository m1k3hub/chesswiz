#include "lexer.h"
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <ctype.h>
#include <sstream>
#include "util.h"
#include "uchar.h"

/* keep in sync with piecedesignator-grammar.txt */

/* lex a piece designator. Lex is used because this is mostly whitespace sensitive.
   regexes are not used because regexes are still a bit flaky cross platform. Also
   Unicode fails to work with them for now.
    
   see the file 
        piecedesignator-grammer.txt
 for the grammar used
*/
Token* Lexer::match_piecedesignator(){
  Token* token=NULL;
  if(!token) token=match_pd_emptypiece();
  if(!token) token=match_pd_nonempty();
  if(!token) token=match_pd_emptysquare();
  return token;
}

/* The following matches a y followed by a non-square identifier, where y is
   [Aa] or [aA] or the unicode symbol for piece*/

PieceDesignatorToken* Lexer::match_pd_Aa_followed_by_id(){
  int x=save();
  if (!(match_string("[Aa]")||
	match_string("[aA]")||
	match_uvalue(UnicodePiece))){
    restore(x);
    return NULL;
  }
  if(!match_squarespecifier().empty()){
    restore(x);
    return NULL;
  }
  int y=save();
  bool seenid=(match_id()!=NULL);
  restore(y);
  if(!seenid){
    restore(x);
    return NULL;
  }
  vector<PieceToken*>pieces{
    new PieceToken('A'),
      new PieceToken('a')};
  vector<SquareToken*>squares{new SquareToken(0,7,0,7)};
  return new PieceDesignatorToken(pieces,squares);
}

/*a piece designator followed by an end_of_pd (so no square designator)*/
Token* Lexer::match_pd_emptysquare(){
  int x=save();
  vector<PieceToken*>pieces=match_piecespecifier();
  if (pieces.empty()) return NULL;
  if (end_of_pd()) {
      SquareToken* squaret=new SquareToken(0,7,0,7);
      return new PieceDesignatorToken(pieces,
				    vector<SquareToken*>{squaret});
  }
  
  restore(x);
  return NULL;
}

//piece designator with empty piece and a square only, like d4, followed by end_of_pd
Token* Lexer::match_pd_emptypiece(){
  //piece designator with missing piece
  int x=save();
  vector<SquareToken*>squares=match_squarespecifier();
  if(squares.empty())return NULL;
  if(end_of_pd()){
    vector<PieceToken*> pieces
    {new PieceToken('A'),
	new PieceToken('a'),
	new PieceToken('_')
	};
    return new PieceDesignatorToken(pieces,
				    squares);
  }
  restore(x);
  return NULL;
}

/* a nonempty piece specifier, a nonempty square specifier, and an end_of_pd()*/

Token* Lexer::match_pd_nonempty(){
  int x=save();
  vector<PieceToken*>pieces=match_piecespecifier();
  vector<SquareToken*>squares=match_squarespecifier();
  if(!squares.empty()&&
     !pieces.empty()&&
     end_of_pd())
    return new PieceDesignatorToken(pieces,squares);
  restore(x);
  return NULL;
}

bool Lexer::end_of_pd(){
  /* True if the current character could represent the character following
     a piece designator*/
  /* Not clear how to handle a string like
     R-2, we say fail. We do allow things like R? */
  char c=peek();
  if (word_constituent(c)) return false;
  int x=save();
  string entity=match_entity_string();
  if(entity.size()){
    restore(x);
    return true;
  }
  if (c=='[' || c==']') return false;
  return true;
}

/*match a piece specifier, either [pieces] or unicodepieces */
vector<PieceToken*>Lexer::match_piecespecifier(){
  vector<PieceToken*>ret = match_unicodepiecespecifier(); //in piecedesignator-unicode.cpp
  if(ret.size())return ret;
  ret = match_compoundpiecespecifier();
  if (ret.empty())
    ret=match_simplepiecespecifier();
  return ret;
}

/* match a simple ASCII piece specifier.*/
vector<PieceToken*>Lexer::match_simplepiecespecifier(){
  vector<PieceToken*>ret;
  char c=peek();
  PieceToken* st=PieceToken::create(c);
  if(!st) return ret;
  forward();
  ret.push_back(st);
  return ret;
}

/*match square specifier*/
/* for the time being a square specifier cannot be '.'
   or its unicode grid character.
This could lead to errors if someone uses
 R.
which is now parsed as two distinct lexemes

*/

vector<SquareToken*>Lexer::match_squarespecifier(){
  vector<SquareToken*>ret=match_simplesquarespecifier();
  if(!ret.empty())return ret;
  ret=match_compoundsquarespecifier();
  return ret;
}

vector<SquareToken*>Lexer::match_simplesquarespecifier(){
  int x=save();
  vector<SquareToken*>ret;
  int minf=-1,maxf=-1,minr=-1,maxr=-1;
  if(match_files(&minf,&maxf)
     && match_ranks(&minr,&maxr))
    ret.push_back(new SquareToken(minf,maxf,minr,maxr));
  else
    restore(x);
  return ret;
}

vector<SquareToken*>Lexer::match_compoundsquarespecifier(){
  vector<SquareToken*>ret;
  int x=save();
  if (!match_char('['))
    return ret;
  while(true){
    if (!ret.empty()){
      if (match_char(']')) break; //success!
      if (!match_char(',')) goto fail; //missing comma
    }
    vector<SquareToken*>nextsquarevec=match_simplesquarespecifier();
    if (nextsquarevec.empty()) goto fail;
    uassert(nextsquarevec.size()==1,"nsv i");
    ret.push_back(nextsquarevec[0]);
  }//the main while loop
  if (!ret.empty()) return ret; //success
 fail: //fail, so restore the state
  ret.clear();
  restore(x);
  return ret;
}


vector<PieceToken*>Lexer::match_compoundpiecespecifier(){
  vector<PieceToken*>ret;
  int x=save();
  if (!match_char('['))
    return ret;
  while(true){
    if (!ret.empty()&&match_char(']'))
      break; //success
    vector<PieceToken*>nextpiecevec=match_simplepiecespecifier();
    if (nextpiecevec.empty()) goto fail;
    uassert(nextpiecevec.size()==1,"internal npv");
    ret.push_back(nextpiecevec[0]);
  }//the main while loop
  if (!ret.empty()) return ret; //success
 fail: //fail, so restore the state
  ret.clear();
  restore(x);
  return ret;
}
