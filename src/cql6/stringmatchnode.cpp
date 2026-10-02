#include "stringmatchnode.h"
#include "stringliteralnode.h"

StringMatchNode::StringMatchNode(Node*targetnode,const string&pattern):
  targetNode(targetnode),thePattern(pattern){
  uassert(targetNode&&targetNode->isString(),
	  "SMN bad args");
  try{
    theRegex=std::regex{thePattern}; //std::regex::multiline does not exist!!
    }
    catch (const std::regex_error& e){
      stringstream s;
      s<<"StringMatch: Malformed regex found in pattern: "
       <<thePattern
       <<" with error given of: "
       <<e.what();
      uassert(false,s.str());
    }
}
bool StringMatchNode::match_position(QPos*qpos){
  return match_stringvalue(qpos,NULL);
}

bool StringMatchNode::match_stringvalue(QPos*qpos,string*stringp){
  string targetstring;
  QGame*qgame=qpos->qgame;
  std::smatch matchresult;
  if (!targetNode->match_stringvalue(qpos,&targetstring))
    return false;
  if (!std::regex_search(targetstring,matchresult,theRegex))
    {qgame->clearRegexHistory();
      return false;}
  if(stringp)
    *stringp=matchresult[0];
  qpos->qgame->registerRegexMatch(matchresult);
  return true;
}

vnode StringMatchNode::children()const{
  return vnode{targetNode};
}

/*this assumes that regexes are copyable which should probably be checked.
  this is a failure mode on bad compilers though*/
void StringMatchNode::deepify(){
  targetNode=targetNode->clone();
}
