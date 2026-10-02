#include "tagsetnode.h"
bool isTagChar(char c){
  return
    c>='a'&&c<='z' ||
    c>='A'&&c<='Z'||
    c>='0'&&c<='9'||
    c=='_'
    ;
}
bool isTagStartChar(char c){
  return isTagChar(c)&&c!='_';
}

   
const vector<string>TagSetNode::forbiddenTags=
  {
   "Black","black","BLACK",
   "White","white","WHITE",
   "Event","event","EVENT",
   "Site","site","SITE",
   "Date","date","DATE",
   "Eco","eco","ECO",
   "Fen","fen","FEN",
   "Round","ROUND",
   "Result","result","RESULT",
   "EventDate","eventdate","eventDate","EVENTDATE"
  };
   
bool TagSetNode::isSettable(const string&tagname,string* message){
  stringstream s;
  if (tagname.empty()){
    s<<"tag is invalid because it is empty";
    if(message) *message=s.str();
    return false;
  }
  else if (!isTagStartChar(tagname[0])){
    s<<"tag name must start with a digit or letter: "<<tagname;
    if(message) *message=s.str();
    return false;
  }
  else
    for (char c:tagname)
      if (!isTagChar(c)){
	s<<"tag names can only contain digits, letters, or underscores: "<<tagname;
    if(message) *message=s.str();
	return false;
      }
  for (const string& badname:forbiddenTags)
    if (tagname==badname){
      s<<"CQL version "
       <<CqlVersion
       <<" does not support using 'tag' or 'settag' with tag names that are close to built in tag names: "
       <<tagname;
    if(message) *message=s.str();
      return false;
    }
  
  if (tagname.size()>5){
    string start=tagname.substr(0,5);
    if (start=="White"||start=="Black"){
      s<<"tag names that begin with the string 'White' or 'Black' cannot be used in this version of CQL here: "
       <<tagname;
    if(message) *message=s.str();
      return false;
    }//start=="White" || ...
  } //tagname.size()>5

  if (tagname.size()>60){
    s<<"This version of CQL only supports tagnames with 'tag' or 'settag' of 60 characters or fewer: "
     <<tagname;
    if(message) *message=s.str();
    return false;
  } //tagname.size()>60

  return true;
}//isSettable()

TagSetNode::TagSetNode(const string &name, Node*node):
  theName(name),
  theNode(node){
  uassert(name.size()>0&&theNode!=NULL,"tagsetnode constr");
  uassert(theNode->isString(),"TagSetNode: argument is not a string");
  uassert(isSettable(name),"TagSetNode::tag cannot be set: internal: ",name);
}

vnode TagSetNode::children()const{return vnode{theNode};
}

bool TagSetNode::match_position(QPos*qpos){
  string val;
  if (!theNode->match_stringvalue(qpos,&val))
    return false;
  if(!CqlNoSetTag)
    qpos->qgame->doSetTag(theName,val);
  return true;
}

void TagSetNode::deepify(){
  theNode=theNode->clone();
}
