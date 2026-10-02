#include "ifnode.h"
IfNode::IfNode(Node* predicate, Node* thenf, Node* elsef):
  predicateFilter(predicate),
  thenFilter(thenf),
  elseFilter(elsef){
  uassert(predicateFilter&&thenFilter,"IfNode: bad args");;
}

bool IfNode::match_position(QPos*qpos){
  if (predicateFilter->match_position(qpos))
    return thenFilter->match_position(qpos);
  if (elseFilter)
    return elseFilter->match_position(qpos);
  return true;
}

bool IfNode::isSet()const{
  return thenFilter->isSet()&&elseFilter&&elseFilter->isSet();
}

bool IfNode::isPosition()const{
  return thenFilter->isPosition()&&elseFilter&&elseFilter->isPosition();
}

bool IfNode::isString()const{
  return thenFilter->isString()&&elseFilter&&elseFilter->isString();
}

bool IfNode::isNumeric()const{
  return thenFilter->isNumeric()&&elseFilter&&elseFilter->isNumeric();
}

bool IfNode::match_positionvalue(QPos*qpos, QPos**value){
  uassert(isPosition(), "Attempt to get value of 'if' filter that is not a position filter");
  if(predicateFilter->match_position(qpos))
    return thenFilter->match_positionvalue(qpos,value);
  else
    return elseFilter->match_positionvalue(qpos,value);
}

bool IfNode::match_stringvalue(QPos*qpos, string*value){
  uassert(isString(), "Attempt to get string value of 'if' filter that is not a string filter");
  if(predicateFilter->match_position(qpos))
    return thenFilter->match_stringvalue(qpos,value);
  else
    return elseFilter->match_stringvalue(qpos,value);
}

bool IfNode::match_count(QPos*qpos, NumValue*v){
  uassert(isNumeric(),"Cannot get a count of this If statement: unexpectedly tried to get count on non-numeric if");
  uassert(thenFilter->isNumeric(),"IfNode: could not get numeric thenfilter");
  if (predicateFilter->match_position(qpos)){
    return thenFilter->match_count(qpos,v);
  }
  if (!elseFilter) return false;
  uassert(elseFilter->isNumeric(),"IfNode: could not get numeric elseFilter");
  return elseFilter->match_count(qpos,v);
}

SquareMask IfNode::getSquares(QPos*qpos){
  uassert(isSet(),"Cannot get a count of this If statement: unexpectedly tried to get count on non-numeric if");
  SetBase*thenset=thenFilter->asSet();
  uassert(thenset,"IfNode: could not get set thenfilter");
  if (predicateFilter->match_position(qpos)){
    return thenset->getSquares(qpos);
  }
  if (!elseFilter) return SquareMask{};
  SetBase*elseset=elseFilter->asSet();
  uassert(elseset,"IfNode: could not get set elseFilter");
  return elseset->getSquares(qpos);
}


  
void IfNode::deepify(){
  predicateFilter=predicateFilter->clone();
  thenFilter=thenFilter->clone();
  if(elseFilter)elseFilter=elseFilter->clone();
}

vnode IfNode::children()const{
  vnode v{predicateFilter};
  myinsert(v,thenFilter);
  if (elseFilter)
    myinsert(v,elseFilter);
  return v;
}


