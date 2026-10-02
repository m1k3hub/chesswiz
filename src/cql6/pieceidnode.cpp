#include "pieceidnode.h"
#include "pieceidvariable.h"
PieceIdNode::PieceIdNode(Node*node){
  uassert(node,"pinnode bad arg");
  pieceidVariable=dynamic_cast<PieceIdVariable*>(node);
  if(!pieceidVariable)
    theSet=node->asSet();
  uassert((pieceidVariable==NULL) + (theSet==NULL)==1, "pinode internal");
}
bool PieceIdNode::match_count(QPos*qpos,NumValue*valuep){
  uassert(qpos&&valuep,"pinode mc");
  if(theSet!=NULL){
    SquareMask mask=theSet->getSquares(qpos);
    if (mask.size()!=1)return false;
    ForMask(square, mask){
      markT pieceid=qpos->getMark(square);
      if(pieceid.isInvalid())return false;
      *valuep=(NumValue)pieceid.getValue();
      return true;
    }
  }
  uassert(pieceidVariable,"pinode int2");
  if(!pieceidVariable->isBound())
    eassert(false,"Piece variable argument to 'pieceid' is unbound: ", pieceidVariable->name);
  *valuep=(NumValue)(pieceidVariable->getPieceId().getValue());
  return true;
}

bool PieceIdNode::match_position(QPos*qpos){
  NumValue value{-1000};
  return match_count(qpos,&value);
}

vnode PieceIdNode::children()const{
  vnode ret;
  if(pieceidVariable) ret.push_back(pieceidVariable);
  else if(theSet) ret.push_back(theSet);
  else uassert(false,"pieceid children");
  return ret;
}

void PieceIdNode::deepify(){
  if(theSet)theSet=theSet->clone();
}


    
