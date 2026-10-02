#include "findnode.h"
FindNode::FindNode(Node*filter,Range*range,bool isfuture, bool isquiet):
  filter(filter),range(range),isFuture(isfuture),isQuiet(isquiet){
  uassert(filter,"bad args to findnode");
}

bool FindNode::isPosition()const{
  return range==NULL;
}

bool FindNode::isNumeric()const{
  return range!=NULL;
}

bool FindNode::match_position(QPos*qpos){
  if (isNumeric()){
    NumValue v{0};
    return match_count(qpos,&v);
  }
  else if (isPosition()){
    QPos* x{NULL};
    return match_positionvalue(qpos,&x);
  }
  uassert(false,"findnode match_position");
  return false;
}

bool FindNode::match_count(QPos*qpos,NumValue*valuep){
  vector<QPos*>matches;
  uassert(isNumeric()&&qpos&&valuep,"fnmc args");
  int nmatches=0;
  for(QPos*q=qpos;q!=NULL;q=next(qpos,q)){
    uassert(q,"fnmcq");
    if(filter->match_position(q)){
      ++nmatches;
      if(CqlCommentLevel>=CommentLevel::Normal&&!isQuiet)
	matches.push_back(q);
    } //filter matches
  }//for each q
  if(!range->valid(nmatches))return false;
  *valuep=nmatches;
  if(CqlCommentLevel>=CommentLevel::Normal && !isQuiet){
    uassert((int)(matches.size())==nmatches,"FindNode:match_count: count/match mismatch");
    for (int i=0;i<nmatches;++i){
      stringstream s;
      s<<"Found "<<i+1<<" of "<<nmatches;
      matches[i]->appendComment(s.str());
    } //for each match
  }//CqlCommentLevel>=Normal
  return true;
}

QPos* FindNode::next(QPos*start, QPos*current){
  uassert(start&&current,"fnn args");
  if(isFuture){
    int currindex=current->index;
    int lastindex=start->lastDescendantIndex;
    uassert(currindex<=lastindex&&currindex>=start->index,"fnn index");
    if(currindex==lastindex)return NULL;
    return start->qgame->getQPos(currindex+1);
  }
  else 
    return current->parent;
}

bool FindNode::match_positionvalue(QPos*qpos,QPos**qposp){
  uassert(isPosition()&&qpos&&qposp,"FindNode args");
  for(QPos*q=qpos;q!=NULL;q=next(qpos,q)){
    uassert(q,"fnmcq 2");
    if(filter->match_position(q)){
      *qposp=q;
      if(CqlCommentLevel>=CommentLevel::Normal&&!isQuiet)
	q->appendComment("Found");
      return true;
    }
  }
  return false;
}

vnode FindNode::children()const{
  return vnode{filter};
}

void FindNode::deepify(){
  filter=filter->clone();
}
