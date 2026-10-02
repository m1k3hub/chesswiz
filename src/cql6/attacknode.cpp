#include "attacknode.h"
#include "attack.h"

AttackNode::AttackNode(SetBase*s, SetBase*t, bool returnfrom, bool returnto):
  attacking(s),
  attacked(t),
  returnAttacking(returnfrom),
  returnAttacked(returnto)
{
  uassert(attacking && attacked,"AttackNode st");
  uassert(returnAttacking+returnAttacked==1,"AttackNode: bad returnAttack/returnAttacking");
}

vnode AttackNode::children()const{
  vnode ret{attacking};
  if (attacked!=attacking)
    ret.push_back(attacked);
  return ret;
}

void AttackNode::compute(QPos*qpos){
  const pieceT* board=qpos->getBoard();
  SquareMask occupied=qpos->getColorMask(WHITE)|qpos->getColorMask(BLACK);
  allAttacked.clear();
  allAttacking.clear();
  SquareMask attackingsquares=attacking->getSquares(qpos);
  SquareMask attackedsquares=attacked->getSquares(qpos);
  if(attackingsquares.empty()||attackedsquares.empty()) return;
  for(squareT attackingsquare=0;attackingsquare<64;++attackingsquare)
    if(attackingsquares.member(attackingsquare)){
    SquareMask attackedmask=Attack::attacksquare(attackingsquare,
				     board[attackingsquare],
				     occupied,
				     attackedsquares);
    if(attackedmask.nonempty()) {
      allAttacking.insert(attackingsquare);
      allAttacked|=attackedmask;}
    }
}

bool AttackNode::match_position(QPos *qpos){
  return getSquares(qpos).nonempty();
}

SquareMask AttackNode::getSquares(QPos*qpos){
  compute(qpos);
  if(returnAttacked)
  return allAttacked;
  else if(returnAttacking)
    return allAttacking;
  uassert(false,"AttackNode::getSquares: nothing to return internal");
  return allAttacking;
}



