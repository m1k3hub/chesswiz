#include "loopnode.h"
LoopNode::LoopNode(Node*node):node(node){
  uassert(node,"Ln arg");
}

vnode LoopNode::children()const{return vnode{node};}
void LoopNode::deepify(){node=node->clone();}
bool LoopNode::match_position(QPos*qpos){
  bool seen=false;
  while(node->match_position(qpos))
    seen=true;
  return seen;
}
