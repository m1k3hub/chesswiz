#include "colorvaluenode.h"
#include "tomovevaluenode.h"
ColorValueNode::ColorValueNode(colorT c) : color(c){
  uassert(color==WHITE||color==BLACK,"cvn bad arg");
}

string ColorValueNode::name(){
  if(color==WHITE) return "white";
  else if (color==BLACK)return "black";
  uassert(false,"cvn int");
  return "";
}

vnode ColorValueNode::children()const{return vnode{};}
void ColorValueNode::deepify(){};
//for transform_members see transform_members.cpp

bool ColorValueNode::match_position(QPos*qpos){
  uassert(false,"unexpected call to match_position on colorvaluenode");
  return false;
}

bool ColorValueNode::match_count(QPos*qpos,NumValue*valuep){
  if(color==WHITE)
    *valuep=ToMoveValueNode::WhiteValue;
  else if (color==BLACK)
    *valuep=ToMoveValueNode::BlackValue;
  else
    uassert(false,"cvn mc int");
  return true;
}
      
