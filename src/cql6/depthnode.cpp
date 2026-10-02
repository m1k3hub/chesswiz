#include "depthnode.h"
bool DepthNode::match_count(QPos*qpos,NumValue*value){
  *value=qpos->getDepth();
  return true;
}
