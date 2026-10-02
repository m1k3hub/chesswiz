#include "node.h"
NumberNode::NumberNode(NumValue v):value(v){}
bool NumberNode::match_count(QPos*qg,NumValue*v){
  *v=value;
  return true;
}
string NumberNode::toString(){
  stringstream s;
  s<<value;
  return s.str();
}

bool NumberNode::match_position(QPos*qpos){
  stringstream s;
  s<<"An attempt to match a position against the number: "<<value
   <<" was made. Although this is not technically an error, it is likely"
   <<" a result of an unexpected parse.";
  eassert(false,s.str());
  return false;
}
    

