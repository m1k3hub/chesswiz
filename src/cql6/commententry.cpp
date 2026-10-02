#include "commententry.h"
#include "node.h"
/* this file is reverted to 9.250 at 9.322 to make settag no longer smart*/

CommentEntry::CommentEntry(QPos*qpos,const string&message):qpos(qpos),message(message){
  uassert(qpos,"CommentEntry arg");
}
string CommentEntry::toString(){
  stringstream s;
  s<<"QPos: "<<qpos->index<<": "<<message;
  return s.str();
}

  
