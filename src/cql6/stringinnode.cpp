#include "stringinnode.h"
StringInNode::StringInNode(Node*l,Node*r,bool computeindex):theLeft(l),theRight(r),computeIndex(computeindex){
  uassert(theLeft&&theRight&&theLeft->isString()&&theRight->isString(),"StringInNode: args");
}

bool StringInNode::match_position(QPos*qpos){
  return match_count(qpos,NULL);
}

bool StringInNode::match_count(QPos*qpos, NumValue*indexp){
  string lefts,rights;
  if (!theLeft->match_stringvalue(qpos,&lefts))
    return false;
  if (!theRight->match_stringvalue(qpos,&rights))
    return false;
  size_t ret=rights.find(lefts);
  if (ret==string::npos)return false;
  eassert(ret<1000000000, "index from string: from indexof x 'in' y, unexpected index > 1e9");
  if(indexp!=NULL) {
    *indexp= (NumValue)ret;
    eassert(*indexp>=0&&*indexp<=rights.size(),"while computing indexof(x y) for strings, unexpected out of range index"); // indexof("" "")== 0
  }
  return true;
}
  
vnode StringInNode::children()const{
  vnode ret{theLeft};
  if (theLeft!=theRight)
    ret.push_back(theRight);
  return ret;
}

void StringInNode::deepify(){
  theLeft=theLeft->clone();
  theRight=theRight->clone();
}
  
  
