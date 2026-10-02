#include "removecommentnode.h"
bool RemoveCommentNode::match_position(QPos*qpos){
  if (CqlNoRemoveComment)return true;
  qpos->deleteOriginalComment=true;
  return true;
}
