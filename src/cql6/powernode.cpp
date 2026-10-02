#include "node.h"
PowerNode::PowerNode(SetBase*s):set(s){
  uassert(set,"powernodes args");
}


bool PowerNode::match_count(QPos*qpos,NumValue*value){
  SquareMask mask=set->getSquares(qpos);
  int power=0;
  const pieceT*board=qpos->getBoard();
  for (int square=0;square<64;++square)
    if(mask.member(square))
      power+= pieceValue(board[square]);
  *value=(NumValue)power;
  return true;
}
    
  
int PowerNode::pieceValue(pieceT p){
  switch (p){
  case BR: case WR: return 5;
  case BN: case WN: return 3;
  case BB: case WB: return 3;
  case BQ: case WQ: return 9;
  case BK: case WK: return 0;
  case BP: case WP: return 1;
  case EMPTY: return 0;
  }
  uassert(false,"piecevalue");
  return 0;
}

    
      
  

  
