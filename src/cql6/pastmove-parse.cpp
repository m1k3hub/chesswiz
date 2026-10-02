#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "nodeheaders.h"

Node* Tokens::match_pastmovenode(){
  if (false)
    ;
  else if (match_keyword("nullmove"))
    return PastMoveNode::makeNullMove();
  else if (match_keyword("o-o"))
    return PastMoveNode::makeOO();
  else if (match_keyword("o-o-o"))
    return PastMoveNode::makeOOO();
  else if (match_keyword("castle"))
    return PastMoveNode::makeCastle();
  else if (match_keyword("enpassant"))
    return PastMoveNode::makeEnPassant();
  else if (match_keyword("enpassantsquare"))
    return set_from_string(
      R"E(notransform 
          if not enpassant 
           [] 
          else if btm 
           down 1 to 
          else 
            up 1 to)E");
  else if (match_keyword("primary"))
    return PastMoveNode::makePrimary();
  else if (match_keyword("secondary"))
    return PastMoveNode::makeSecondary();
  else return NULL;
}

