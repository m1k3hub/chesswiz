#include "currentnode.h"
CurrentNode::CurrentNode(){}
bool CurrentNode::match_position(QPos*qpos){return true;}
void CurrentNode::deepify(){}
CurrentNode* CurrentNode::clone(){return this;}
vnode CurrentNode::children()const{return vnode{};}
bool CurrentNode::match_positionvalue(QPos*qpos,QPos**valuep){
  *valuep=qpos;
  return true;
}
