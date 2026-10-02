#include "squareloopnode.h"
#include "squarevariable.h"
SquareLoopNode::SquareLoopNode(SquareVariable*v, SetBase*trgt, Node*body, bool all):variable(v),target(trgt),theBody(body),isAll(all){
  uassert(variable&&variable->isUnbound(),"existsnode, internal, var bound");
  uassert(theBody,"SquareLoopNode: no body");
}

bool SquareLoopNode::isSet()const{
  return !isAll;
}

//If allp is set set that else set setp
void SquareLoopNode::execute(QPos*qpos, SquareMask *setp, bool * allp){
  uassert(isAll==(allp!=NULL),"SquareLoopNode::execute allp");
  if(allp)uassert(!setp,"SquareLoopNode execute allp setp");
  if(!allp)uassert(setp,"SquareLoopNode execute setp allp");
  if(allp)*allp=true;
  if(setp)setp->clear();
  SquareMask targetmask;
  if(target) targetmask=target->getSquares(qpos);
  else targetmask=SquareMask::all();
  ForMask(sq,targetmask){
    bool bodyret=match_body(sq,qpos);
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

bool SquareLoopNode::match_body(squareT square, QPos* qpos){
  int mark=qpos->markComments();
  uassert(square_valid(square),"SquareLoopNode mf 0");
  if(variable->isBound()){
    stringstream s;
    s<<"While preparing to execute a 'square...in' filter with variable: "
     <<variable->name
     <<" the variable was unexpectedly already bound to a value. This "
     <<" may indicate that the square filter is in the scope of another square filter which "
     <<" is also trying to use that same variable."
      ;
    eassert(false,s.str());
  }
  variable->bindSquare(square);
  bool ret=theBody->match_position(qpos);
  if(!ret)qpos->restoreComments(mark);
  variable->unbind();
  return ret;
}

vnode SquareLoopNode::children()const{
  vnode v{theBody};
  if(target&&target!=theBody) v.push_back(target);
  return v;
}
void SquareLoopNode::deepify(){
  theBody=theBody->clone();
  if(target)target=target->clone();
}

bool SquareLoopNode::match_position(QPos*qpos){
  if(isAll){
    int mark=qpos->markComments();
    bool all=false;
    execute(qpos,NULL,&all);
    if(!all)qpos->restoreComments(mark);
    return all;
  }
  SquareMask ret=getSquares(qpos);
  return ret.nonempty();
}

SquareMask SquareLoopNode::getSquares(QPos*qpos){
  SquareMask ret;
  uassert(!isAll,"SquareLoopNode::getSet() unexpectedly call when isAll is set to true");
  execute(qpos,&ret,NULL);
  return ret;
}
  
