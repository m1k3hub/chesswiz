#include "currenttransformnode.h"
//below was mainly copied from old 9.250 commentcurrentransform.cpp, I hope it works
CurrentTransformNode::CurrentTransformNode(){
}
  
bool CurrentTransformNode::match_position(QPos*qpos){
  eassert(false,"attempt to use 'currenttransform' for whether it matches rather than its string value, but the filter always matches");
  return false;
}

bool CurrentTransformNode::match_stringvalue(QPos*qpos,string*valuep){
  uassert(valuep&&qpos,"ctmmsv: args");
  if (theTransforms.empty()){
    *valuep="<>";
    return true;
  }
  stringstream s;
  int ntransforms=(int)(theTransforms.size());
  for (int i=ntransforms-1;i>=0;--i){
    auto t=theTransforms.at(i);
    if(t->isIdentity())continue;
    s<<t->toString()<<' ';
  }
  string ret=s.str();
  while (ret.size()&&ret.back()==' ')ret.pop_back();
  while (ret.size()&&ret.front()==' ')ret=ret.substr(1);
  ret=string("<")+ret+">";
  *valuep=ret;
  return true;
}

void CurrentTransformNode::deepify(){
}

void CurrentTransformNode::transform_members(Transform*t){
  uassert(t,"commentcurrenttransform arg");
  theTransforms.push_back(t);
}

/* I think this satisfies the weak ordering requirements of C++, see https://en.cppreference.com/w/cpp/named_req/Compare */

bool CurrentTransformNode::transformmemberless(const Node* node)const{
  const CurrentTransformNode*other=dynamic_cast<const CurrentTransformNode*>(node);
  uassert(other!=NULL,"CommentCurrentTransform tmless arg");
  return false; 
}
