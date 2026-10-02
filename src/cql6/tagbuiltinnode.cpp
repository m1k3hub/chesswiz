#include "tagbuiltinnode.h"
vector<string>TagBuiltInNode::builtInTags{
  "Black",
    "White",
    "Event",
    "EventDate",
    "Site",
    "Date",
    "ECO",
    "FEN"};

TagBuiltInNode::TagBuiltInNode(const string& name):theName(name){
  uassert(isBuiltInTag(theName),
	  "Invalid tag argument: ",theName);
}

bool TagBuiltInNode::isBuiltInTag(const string&name){
  return util::member(builtInTags,name);
}

bool TagBuiltInNode::match_position(QPos*qpos){
  return match_game(qpos->qgame);
}

bool TagBuiltInNode::match_game(QGame*qgame){
  return match_stringvalue_game(qgame,NULL);
}

bool TagBuiltInNode::match_stringvalue_game(QGame*qgame, string*stringp){
  string target=QMarkBoard::getTagBuiltIn(qgame,theName);
  if (target.empty()) return false;
  if(stringp) *stringp=target;
  return true;
}


bool TagBuiltInNode::match_stringvalue(QPos*qpos, string*stringp){
  return match_stringvalue_game(qpos->qgame,stringp);
}
  
//but see transform_members.cpp and transformcompare.cpp for relevant transforms
void TagBuiltInNode::deepify(){
}
