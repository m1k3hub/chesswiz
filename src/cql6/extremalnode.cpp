#include "extremalnode.h"
ExtremalNode::ExtremalNode(vector<Node*>nodes, bool ismax):
  theNodes(nodes),theIsMax(ismax){
    uassert(theNodes.size()>1,"ExtremalNode: argsize");
    for(auto n:theNodes)
      uassert(n!=NULL&&n->isSortable()&&
	      n->isString()==theNodes[0]->isString()&&
	      n->isNumeric()==theNodes[0]->isNumeric(),"ExtremalNode: argument type");
    sortValueType = (theNodes[0]->isString())? SortValueType::String
      : SortValueType::Numeric;
}
bool ExtremalNode::match_position(QPos*qpos){
  eassert(false,"Attempt to match a position for filter of  max or min filter. Although legal this is likely an error.");
  return true;
}

bool ExtremalNode::match_count(QPos*qpos,NumValue*value){
  uassert(qpos&&value,"emmc");
  uassert(sortValueType==SortValueType::Numeric,"ExtremalNode:match_count: bad arg");
  int originalMark=qpos->markComments();
  bool seenbest{false};
  NumValue bestsofar{0};
  for(auto node:theNodes){
    int currentMark=qpos->markComments();
    if(!node->match_count(qpos,value));
    else if(!seenbest){
      bestsofar=*value;
      seenbest=true;}
    else if(theIsMax && *value>bestsofar ||
            !theIsMax && *value< bestsofar){
      bestsofar=*value;
      qpos->deleteComments(originalMark,currentMark);
    }
    else if (theIsMax&&*value<bestsofar ||
	     !theIsMax&&*value>bestsofar)
      qpos->restoreComments(currentMark);
    else if (*value==bestsofar);
    else
      uassert(false,"extremalvalue:matchcount: logic");
  }//for node:theNodes
  if (!seenbest)return false;
  *value=bestsofar;
  return true;
}

bool ExtremalNode::match_stringvalue(QPos*qpos,string*value){
  uassert(qpos&&value,"emmc");
  uassert(sortValueType==SortValueType::String,"ExtremalNode:match_count: bad arg");
  int originalMark=qpos->markComments();
  bool seenbest{false};
  string bestsofar;
  for(auto node:theNodes){
    int currentMark=qpos->markComments();
    if(!node->match_stringvalue(qpos,value));
    else if(!seenbest){
      bestsofar=*value;
      seenbest=true;}
    else if(theIsMax && *value>bestsofar ||
            !theIsMax && *value< bestsofar){
      bestsofar=*value;
      qpos->deleteComments(originalMark,currentMark);
    }
    else if (theIsMax&&*value<bestsofar ||
	     !theIsMax&&*value>bestsofar)
      qpos->restoreComments(currentMark);
    else if (*value==bestsofar);
    else
      uassert(false,"extremalvalue:matchcount: logic");
  }//for node:theNodes
  if (!seenbest)return false;
  *value=bestsofar;
  return true;
}

void ExtremalNode::deepify(){
  for (auto n: theNodes) n=n->clone();
}

vnode ExtremalNode::children()const{
  return theNodes;
}

string ExtremalNode::name(){
  if(theIsMax)return "max";
  return "min";
}
					     
bool ExtremalNode::isNumeric()const{
  return sortValueType==SortValueType::Numeric;
}

bool ExtremalNode::isString()const{
  return sortValueType==SortValueType::String;
}

