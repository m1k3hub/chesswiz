#include "plynode.h"
bool PlyNode::match_count(QPos*qpos,NumValue*value){
  *value=qpos->getPly();
  return true;
}
