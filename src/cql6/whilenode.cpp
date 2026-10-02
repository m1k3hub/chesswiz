#include "whilenode.h"
WhileNode::WhileNode(Node*test,Node*body):theTest(test),theBody(body){
  uassert(theTest&&theBody,"Wn arg");
}

vnode WhileNode::children()const{
  vnode ret{theTest};
  myinsert(ret,theBody);
  return ret;
}

void WhileNode::deepify(){
  theTest=theTest->clone();
  theBody=theBody->clone();
}

bool WhileNode::match_position(QPos*qpos){
  while(theTest->match_position(qpos))
    theBody->match_position(qpos);
  return true;
}
