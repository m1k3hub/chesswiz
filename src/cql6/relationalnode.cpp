#include "relationalnode.h"
vector<string>* RelationalNode::theAllNames{NULL};
vector<string>* RelationalNode::thePositionComparisonNames{NULL};
RelationalNode::RelationalNode(string n,
			       Node* l,
			       Node* r):name(n),
					     left(l),
					     right(r)
{
  uassert(left&&right,"relational nodes args");
  uassert(left->isNumeric()&&right->isNumeric() ||
	  left->isString()&&right->isString()||
	  left->isPosition()&&right->isPosition(),
	  "RelationalNode: mismatch typed arguments: constructor");
  uassert(name!="!=","Invalid '!=' argument to RelationalNode");
  uassert(name.size(),"RelationalNode: name argument");
  if(myindex(*allNames(),name)<0)
    uassert(false,"Invalid name to RelationalNode: ",name);
}

const vector<string>* RelationalNode::allNames(){
  if (!theAllNames)
    theAllNames= new vector<string>
      {
       "<",
       ">",
       "==",
       "!=",
       "<=",
       ">=",
       "[<]",
       "[<=]",
       "[>]",
       "[>=]"
      };
  return theAllNames;
}

const vector<string>* RelationalNode::positionComparisonNames(){
  if (!thePositionComparisonNames)
    thePositionComparisonNames= new vector<string>
      {
       "boardequals"
      };
  return thePositionComparisonNames;
}

bool RelationalNode::match_count(QPos*qpos, NumValue*valuep){
  uassert(isNumeric(),"RelationalNode internal: relation node count type");
  int mark=qpos->markComments();
  NumValue val1{-1000};
  NumValue val2{-1000};
  if (left->match_count(qpos,&val1)&&
      right->match_count(qpos,&val2)&&
      compare(val1,val2)){
    if(valuep) *valuep=val1;
    return true;
  }
  qpos->restoreComments(mark);
  return false;
}

bool RelationalNode::match_stringvalue(QPos*qpos, string*valuep){
  uassert(isString(),"comparing a non-string 'if' node, internal");
  int mark=qpos->markComments();
  string val1, val2;
  if (left->match_stringvalue(qpos,&val1)&&
      right->match_stringvalue(qpos,&val2)&&
      compare(val1,val2)){
    if(valuep) *valuep=val1;
    return true;
  }
  qpos->restoreComments(mark);
  return false;
}

bool RelationalNode::match_positionvalue(QPos*qpos,QPos**valuep){
  uassert(isPosition(),"comparing a non-position in relational node");
  int mark=qpos->markComments();
  QPos* val1{NULL};
  QPos* val2{NULL};
  if(left->match_positionvalue(qpos,&val1)&&
     right->match_positionvalue(qpos,&val2)&&
     compare(val1,val2)){
    if(valuep)*valuep=val1;
    return true;
  }
  qpos->restoreComments(mark);
  return false;
}

bool RelationalNode::match_position(QPos*qpos){
  if (isString())
    return match_stringvalue(qpos,NULL);
  else if (isNumeric())
    return match_count(qpos,NULL);
  else if (isPosition())
    return match_positionvalue(qpos,NULL);
  uassert(false, "RN match_position");
  return false;
}


bool RelationalNode::compare(QPos* v1, QPos* v2){
  uassert(v1&&v2,"relationalnode::compare bad arguments");
  if (name=="<") return v1->index<v2->index;
  if (name==">") return v1->index>v2->index;
  if (name=="==") return v1==v2;
  if (name=="<=") return v1->index<=v2->index;
  if (name==">=") return v1->index>=v2->index;
  if (name=="!=") return v1->index!=v2->index;
  if(name=="[<]") return v1->index<v2->index&&
		    v2->index<=v1->lastDescendantIndex;
  if(name=="[>]") return v1->index>v2->index&&
		    v1->index<=v2->lastDescendantIndex;
  if(name=="[<=]") return v1->index<=v2->index&&
		     v2->index<=v1->lastDescendantIndex;
  if(name=="[>=]") return v1->index>v2->index&&
		    v1->index<=v2->lastDescendantIndex;
  uassert(false,"relational node: bad name: ", name);
  return false;
}
  
bool RelationalNode::compare(NumValue v1, NumValue v2){
  if (name=="<") return v1<v2;
  if (name==">") return v1>v2;
  if (name=="==") return v1==v2;
  if (name=="<=") return v1<=v2;
  if (name==">=") return v1>=v2;
  if (name=="!=") return v1!=v2;
  uassert(false,"rncompare: bad name: ", name);
  return false;
}

bool RelationalNode::compare(const string& v1, const string& v2){
  if (name=="<") return v1<v2;
  if (name==">") return v1>v2;
  if (name=="==") return v1==v2;
  if (name=="<=") return v1<=v2;
  if (name==">=") return v1>=v2;
  if (name=="!=") return v1!=v2;
  uassert(false,"rncompare: bad name: ", name);
  return false;
}

vnode RelationalNode::children()const{
  if (left==right) return vnode{left};
  return vnode{left,right};
}

bool RelationalNode::isNumeric()const{
  return left->isNumeric()&&right->isNumeric();
}

bool RelationalNode::isPosition()const{
  return left->isPosition()&&right->isPosition();
}

bool RelationalNode::isString()const{
  return left->isString()&&right->isString();
}

void RelationalNode::deepify(){
  left=left->clone();
  right=right->clone();}

  
  
  
      
  
