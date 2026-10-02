#include "echonode.h"
EchoNode::EchoNode(PositionVariable*svar,PositionVariable*tvar,Node*filter,bool searchall, bool isquiet):
  sourcevar(svar),targetvar(tvar),theFilter(filter),searchAll(searchall),isQuiet{isquiet}{
  uassert(sourcevar&&targetvar&&theFilter,"EchoNode bad args");
  if(filter->isNumeric()) theIsNumeric=true;
}

bool EchoNode::compute(QPos*qpos){
  int mark=qpos->markComments();
  uassert(qpos,"rnmp arg");
  uassert(sourcevar->isUnbound(),"In EchoNode the source variable is unexpectedly already bound to a position: ",sourcevar->name);
  uassert(targetvar->isUnbound(),"In EchoNode the target variable is unexpectedly already bound to a position: ",targetvar->name);
  sourcevar->bindPosition(qpos);
  QGame* qgame=qpos->qgame;
  uassert(qgame,"rnmp qgame");
  int nmatches=0;
  currentValue=-100000000;
  maxValue=-100000000;
  for(QPos*currpos:qgame->allQPos) if (searchAll||currpos!=qpos){
      int currposmark=qpos->markComments();
      uassert(currposmark>=mark,"echonode bad mark");
      targetvar->bindPosition(currpos);
      if (theIsNumeric){
	if(!theFilter->match_count(currpos,&currentValue)) continue;
      }
      else if(!theFilter->match_position(currpos)) continue;
      nmatches++;
      if(CqlCommentLevel>CommentLevel::Quiet && !isQuiet){
	QPos*L=QPos::lca(qpos,currpos);
	if(qpos!=L && currpos!=L)
	  L->appendComment("LCA");
	qpos->appendComment(sourcevar->name);
	currpos->appendComment(targetvar->name);
	stringstream s;
	s<<"-->"<<qpos->idString();
	currpos->appendComment(s.str());
	stringstream s2;
	s2<<"<--"<<currpos->idString();
	qpos->appendComment(s2.str());
      }//CommentLevel>Quiet
      if(isSort){       //this section is slightly modified in 9.223
	if(currentValue<=maxValue)
	  qpos->restoreComments(currposmark); //from mark, bug #sortecho1
	else
	  qpos->deleteComments(mark,currposmark);
      }//if (isSort)
      if(theIsNumeric&&currentValue > maxValue) maxValue=currentValue; //modified in 9.223 to always update maxValue
    }//forqpos
  sourcevar->unbind();
  if(targetvar->bound)targetvar->unbind();
  uassert(sourcevar->isUnbound()&&targetvar->isUnbound(),"echonode internal");
  bool ret=(nmatches>0); 
  if(!ret) qpos->restoreComments(mark); //This isn't really necessary
  return ret;
}

bool EchoNode::match_position(QPos*qpos){
  return compute(qpos);
}

bool EchoNode::isNumeric()const{
  return theIsNumeric;
}

bool EchoNode::match_count(QPos*qpos,NumValue*valuep){
  uassert(qpos&&valuep,"enmc args");
  if(compute(qpos)){
    *valuep=maxValue; //added for 9.223 due to bug #sortecho2
    return true;
  }
  return false;
}

vnode EchoNode::children()const{
  vnode ret{sourcevar};
  if(targetvar!=sourcevar) ret.push_back(targetvar);
  myinsert(ret,theFilter);
  return ret;
}
  
void EchoNode::deepify(){
  theFilter=theFilter->clone();
}

void EchoNode::setIsSort(){
  uassert(!isSort,"setIsSort echo already sort");
  isSort=true;
}
