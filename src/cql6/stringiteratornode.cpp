#include "stringiteratornode.h"
#include <regex>
using std::sregex_iterator;
StringIteratorNode::StringIteratorNode(
		   Node*target,
		   const string&pattern,
		   Node*body):
  theTarget(target),thePattern(pattern),theBody(body){
  uassert(theTarget&&theBody&&theTarget->isString(),"sin null arg");
    try{
      theRegex=std::regex{thePattern}; //std::multiline  just fails!
    }
    catch (const std::regex_error& e){
      stringstream s;
      s<<"Malformed regex found in pattern: "
       <<thePattern
       <<" with error given of: "
       <<e.what();
      eassert(false,s.str());
    } //catch
}

bool StringIteratorNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  string targetstring;
  if(!theTarget->match_stringvalue(qpos,&targetstring)){
    qpos->restoreComments(mark);
    return false;
  }
  sregex_iterator beginiter=sregex_iterator(targetstring.cbegin(),
					    targetstring.cend(),
					    theRegex);
  sregex_iterator enditer=sregex_iterator();
  qpos->qgame->clearRegexHistory();
  for(std::sregex_iterator iter = beginiter; iter!=enditer;++iter){
    std::smatch match = *iter;
    uassert(!match.empty(),"StringIteratorNode: unexpectedly got an empty match");
    qpos->qgame->registerRegexMatch(match);
    theBody->match_position(qpos);
  }
  return true;
}

vnode StringIteratorNode::children()const{
  vnode ret{theTarget};
  myinsert(ret,theBody);
  return ret;
}

void StringIteratorNode::deepify(){
  theTarget=theTarget->clone();
  theBody=theBody->clone();
}
  
    


    
     
     

  
