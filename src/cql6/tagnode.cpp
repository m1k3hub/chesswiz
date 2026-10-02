#include "tagnode.h"
#include "tagbuiltinnode.h"
#include "tagsetnode.h"
#include "node.h"
/*
  The 
        tag name
   filter for a string literal name depends on the classification of name.
  There are three class of names:
     Class 1: Cql-BuiltIns. These have specific query methods associated to them,
      checked via TagBuiltInNode::isBuiltInTag(string)
     Class 2: Tags separately stored. These must not be too similar
       to a CQL-BuiltIn or to some other names like FEN or start with White or Black.
       These are true if 
          TagSetNode::isSettable(string name,string* message=NULL)
     Class 3: SCID tags. These are tags not in 1 or 2 that are handled by SCID. 
       These cannot currently be queried by CQL.

  There are also three accessor nodes: TagSetNode, TagBuiltInNode and TagNode.
  TagSetNode sets tag values of class 2. TagNode reads values of class 2. The tag
  node handles classes 1 and 2. The settag node handles values of class 3.
*/


Node* TagNode::create(string name){
  uassert(isQueryable(name),"TagNode::create: invalid name: ",name);
  if (TagBuiltInNode::isBuiltInTag(name))
    return new TagBuiltInNode(name);
  return new TagNode(name);
}

bool TagNode::isQueryable(const string& name, string*message){
  if (TagBuiltInNode::isBuiltInTag(name))
    return true;
  return TagSetNode::isSettable(name,message);
}

TagNode::TagNode(string name):theName(name){
  uassert(theName.size(),"TagNode constructor");
  uassert (!TagBuiltInNode::isBuiltInTag(theName),
	   "TagNode: did not expect a built-in name as argument",theName);
}

bool TagNode::match_position(QPos*qpos){
  return match_game(qpos->qgame);
}

bool TagNode::match_game(QGame*qgame){
  return match_stringvalue_game(qgame,NULL);
}

bool TagNode::match_stringvalue_game(QGame*qgame,string*sval){
  TagSection*tagsection=qgame->getTagSection();
  return tagsection->getGameValue(theName,sval);
}

bool TagNode::match_stringvalue(QPos*qpos,string*sval){
  TagSection*tagsection=qpos->qgame->getTagSection();
  return tagsection->getGameValue(theName,sval);
}


