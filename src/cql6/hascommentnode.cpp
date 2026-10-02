#include "hascommentnode.h"
#include "util.h"


HasCommentNode::HasCommentNode(int nag):nag(nag){
  uassert(nag>0&&nag<=255,"HasCommentNode: invalid nag parameter");
  nagValid=true;
}

HasCommentNode::HasCommentNode(){
  nagValid=false;
}

bool HasCommentNode::match_position(QPos*qpos){
  if (nagValid)
    return qpos->hasNag(nag);
  else return match_stringvalue(qpos,NULL);
}

bool HasCommentNode::match_stringvalue(QPos*qpos,string*stringp){
  if(nagValid)
    uassert(false,"An internal error associated with 'hascomment' - attempt to take string value of node but 'hascomment' was specified with a NAG parameter of: ", std::to_string(nag));
  if(qpos->originalComment.empty())return false;
  if (stringp)
    *stringp=qpos->originalComment;
  return true;
}

int HasCommentNode::nag_from_string(const string& v){
  if(v.empty()) return 0;
  if(v=="!") return 1;
  if(v=="?") return 2;
  if(v=="!!") return 3;
  if(v=="??") return 4;
  if(v=="!?") return 5;
  if(v=="?!") return 6;
  if(v=="=") return 10;
  if(v=="+/=") return 14;
  if(v=="=/+") return 15;
  if(v=="+/-") return 16;
  if(v=="-/+") return 17;
  if(v=="+-") return 18;
  if(v=="-+") return 19;
  if(v[0]!='$')return 0;
  if(v.size()==1) return 0;
  string numstring=v.substr(1);
  int val=0;
  bool valid=util::nonnegativeIntValue(numstring,&val);
  if(!valid)return 0;
  uassert(val>=0,"match nag error");
  return val;
}
  
