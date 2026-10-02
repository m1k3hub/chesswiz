#include "abortnode.h"
AbortNode::AbortNode(string message):theMessage(message){}
bool AbortNode::match_position(QPos*qpos){
  uassert(false,"AbortNode uassert failure at: ",theMessage);
  return false;
}
