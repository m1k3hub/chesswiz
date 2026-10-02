#include "virtualmainlinenode.h"
bool VirtualMainlineNode::match_position(QPos*qpos){
  uassert(qpos,"virtualmainline: bad arg");
  return qpos->virtualmainline();
}
