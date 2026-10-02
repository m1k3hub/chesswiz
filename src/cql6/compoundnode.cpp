#include "compoundnode.h"
vnode CompoundNode::children()const{
  return vnode{specs.begin(),specs.end()};
}

CompoundNode::CompoundNode(vector<Node*> ss):specs(ss){
  uassert(specs.size(),"Cannot create CompoundNode with 0 elements");
  for(auto s: specs){
    uassert(s,"null input to positionnode");
  }
}

Node* CompoundNode::last()const{
  uassert(!specs.empty(),"PN last empty");
  return specs.back();
}

bool CompoundNode::match_position(QPos*qpos){
  int cstart=qpos->markComments();
  for(Node* spec:specs)
    if(!spec->match_position(qpos)){
      qpos->restoreComments(cstart);
      return false;
    }
  return true;
}

bool CompoundNode::isNumeric()const{
  auto l =last();
  return l->isNumeric();
}

bool CompoundNode::isPosition()const{
  auto l=last();
  return l->isPosition();
}


bool CompoundNode::isSet()const{
  return last()->isSet();
}

bool CompoundNode::isString()const{
  return last()->isString();
}

SquareMask CompoundNode::getSquares(QPos*qpos){
  uassert(isSet(),"Compound filter used as square filter but  last element of the Compound filter is not a square filter");
  int len = (int)(specs.size());
  SquareMask ret;
  for (int i=0;i<len-1;++i){
    auto f=specs[i];
    uassert(f,"positionnode null spec");
    if (!f->match_position(qpos))
      return ret;
  }
  SetBase* set= last()->asSet();
  uassert(set,"unexpected null last spec set in positionnode getsquares");
  ret=set->getSquares(qpos);
  return ret;
}

bool CompoundNode::match_count(QPos*qpos, NumValue*v){
  uassert(v&&qpos,"PNmc args");
  uassert(isNumeric(),"Compound filter used as numeric filter but last element is not numeric");
  int mark=qpos->markComments();
  int len = (int)(specs.size());
  for (int i=0;i<len-1;++i){
    auto f=specs[i];
    uassert(f,"compoundnode null spec");
    if (!f->match_position(qpos)){
      qpos->restoreComments(mark);
      return false;
    }
  }
  Node* numeric= last();
  uassert(numeric->isNumeric(),"unexpected null last spec numeric in compoundnode getsquares");
  bool ret= numeric->match_count(qpos,v);
  if (!ret) qpos->restoreComments(mark);
  return ret;
}

bool CompoundNode::match_positionvalue(QPos*qpos, QPos**v){
  uassert(v&&qpos,"PNmcp args");
  uassert(isPosition(),"Compound filter used as position filter but last element is not a position filter");
  int mark=qpos->markComments();
  int len = (int)(specs.size());
  for (int i=0;i<len-1;++i){
    auto f=specs[i];
    uassert(f,"compoundnode null spec");
    if (!f->match_position(qpos)){
      qpos->restoreComments(mark);
      return false;
    }
  }
  Node* pos= last();
  uassert(pos->isPosition(),"unexpected null last spec numeric in compoundnode match_positionvalue");
  bool ret=pos->match_positionvalue(qpos,v);
  if(!ret)qpos->restoreComments(mark);
  return ret;
}

    



    
bool CompoundNode::match_stringvalue(QPos*qpos, string*v){
  uassert(v&&qpos,"PNmcs args");
  uassert(isString(),"Compound filter used as string filter but last element is not string");
  int mark=qpos->markComments();
  int len = (int)(specs.size());
  for (int i=0;i<len-1;++i){
    auto f=specs[i];
    uassert(f,"compoundnode null spec");
    if (!f->match_position(qpos)){
      qpos->restoreComments(mark);
      return false;
    }
  }
  Node* stringnode= last();
  uassert(stringnode->isString(),"unexpected  last spec not string in compoundnode");
  bool ret= stringnode->match_stringvalue(qpos,v);
  if (!ret) qpos->restoreComments(mark);
  return ret;
}

bool CompoundNode::isGameFilter()const{
  for (Node*spec:specs)
    if(!spec->isGameFilter())return false;
  return true;
}
