/*This file should be kept in sync with squarenode.cpp*/
#include "pieceloopnode.h"
#include "pieceidvariable.h"
PieceLoopNode::PieceLoopNode(PieceIdVariable*v, SetBase*trgt, Node*body, bool all):variable(v),target(trgt),theBody(body),isAll(all){
  uassert(variable&&variable->isUnbound(),"existsnode, internal, var bound");
  uassert(theBody,"PieceLoopNode: no body");
}

bool PieceLoopNode::isSet()const{
  return !isAll;
}

//If allp is set set that else set setp
void PieceLoopNode::execute(QPos*qpos, SquareMask *setp, bool * allp){
  uassert(isAll==(allp!=NULL),"PieceLoopNode::execute allp");
  if(allp)uassert(!setp,"PieceLoopNode execute allp setp");
  if(!allp)uassert(setp,"PieceLoopNode execute setp allp");
  if(allp)*allp=true;
  if(setp)setp->clear();
  SquareMask targetmask;
  if(target) targetmask=target->getSquares(qpos);
  else targetmask=SquareMask::all();
  ForMask(sq,targetmask){
    markT pieceid=qpos->getMark(sq);
    if(!pieceid.isValid())continue;
    uassert(qpos->getSquare(pieceid)==sq,"pieceloopnode pieceid square assertion");
    bool bodyret=match_body(pieceid,qpos);
    if(bodyret&&!setp)continue;
    else if (bodyret&&setp)
      setp->insert(sq);
    else if (!bodyret&&!setp){
      uassert(isAll,"squarenode execute internal setp");
      *allp=false;
      return;
    }
    else if (!bodyret&&setp)
      continue;
    else
      uassert(false,"squarenode execute internal loop");
  }//ForMask
}

bool PieceLoopNode::match_body(markT pieceid, QPos* qpos){
  int mark=qpos->markComments();
  uassert(pieceid.isValid(),"PieceLoopNode mf 0");
  if(variable->isBound()){
    stringstream s;
    s<<"While preparing to execute a 'piece...in' filter with variable: "
     <<variable->name
     <<" the variable was unexpectedly already bound to a value. This "
     <<" may indicate that the piece filter is in the scope of another piece filter which "
     <<" is also trying to use that same variable."
      ;
    eassert(false,s.str());
  }
  variable->bindPieceId(qpos,pieceid);
  bool ret=theBody->match_position(qpos);
  if(!ret)qpos->restoreComments(mark);
  variable->unbind();
  return ret;
}

vnode PieceLoopNode::children()const{
  vnode v{theBody};
  if(target&&target!=theBody) v.push_back(target);
  return v;
}
void PieceLoopNode::deepify(){
  theBody=theBody->clone();
  if(target)target=target->clone();
}

bool PieceLoopNode::match_position(QPos*qpos){
  if(isAll){
    int mark=qpos->markComments();
    bool all=false;
    execute(qpos,NULL,&all);
    if(!all)qpos->restoreComments(mark);
    return all;
  }
  SquareMask ret=getSquares(qpos);
  return ret.nonempty(); //we don't need to restore marks here, done in body
}

SquareMask PieceLoopNode::getSquares(QPos*qpos){
  SquareMask ret;
  uassert(!isAll,"PieceLoopNode::getSet() unexpectedly call when isAll is set to true");
  execute(qpos,&ret,NULL);
  return ret;
}

  
