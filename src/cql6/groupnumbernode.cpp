#include "groupnumbernode.h"
GroupNumberNode::GroupNumberNode(int group,const string&location,bool computeindex):
  theGroup(group),
  theLocation(location),
  computeIndex{computeindex}{
  uassert(theGroup>=0&&theGroup<100,"GroupNumberNode: invalid group");
}

bool GroupNumberNode::match_position(QPos*qpos){
  return match_groupindex(qpos,NULL);
}

bool GroupNumberNode::match_groupindex(QPos*qpos, NumValue*valp){
  RegexHistory*history=qpos->qgame->getRegexHistory();
  if (history->getNgroups()<=theGroup){
    stringstream s;
    s<<"Not enough groups in regex: The expression\n"
     <<"     \\-" <<theGroup<<"\n"
     <<" at location: " << theLocation
     <<" used an invalid group number.\n ";
    if (history->getNgroups()==0)
      s<<"The last regular expression match failed to match, so no groups can be accessed";
    else
      s<<"The maximum allowed group number here is: "<<history->getNgroups()-1;
    eassert(false,s.str());
  }
  int grouppos= history->groupStart(theGroup);
  if (grouppos<0)return false;
  if (valp) *valp=(NumValue)grouppos;
  return true;
}

void GroupNumberNode::makeComputeIndex(){
  uassert(!computeIndex,"GroupNumberNode: attempt to set this node to return the index, but it already does; some kind of parse error");
  computeIndex=true;
}

bool GroupNumberNode::match_count(QPos*qpos,NumValue*valp){
  uassert(isNumeric(),"groupNumberNode: Unexpected attempt to get index from group string value");
  return match_groupindex(qpos,valp);
}

bool GroupNumberNode::match_stringvalue(QPos*qpos,string*stringp){
  uassert (isString(),"groupnumberNode: Unexpected attempt to get string from group index node");
  QGame*qgame=qpos->qgame;
  RegexHistory* history=qgame->getRegexHistory();
  if (history->getNgroups()<=theGroup){
    stringstream s;
    s<<"Not enough groups in regex: The expression\n"
     <<"     \\" <<theGroup<<"\n"
     <<" at location: " << theLocation
     <<" used an invalid group number.\n ";
    if (history->getNgroups()==0)
      s<<"The last regular expression match failed to match, so no groups can be accessed";
    else
      s<<"The maximum allowed group number here is: "<<history->getNgroups()-1;
    eassert(false,s.str());
  }
  return history->groupString(theGroup, stringp);
}

  
