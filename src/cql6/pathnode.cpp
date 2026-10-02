#include "pathnode.h"
#include "pathlastpositionnode.h"
/*the constructor is only invoked in path-parse. Keep in sync*/
PathNode::PathNode(vector<PathCon*>cs,
		   Range*r,
		   Focus*focus,
		   bool nestbanparam,
		   bool firstmatch,
		   bool isprimary,
		   bool returnfinish,
		   Node* themax,
		   const vector<Variable*>&atomicvariables,
		   bool usepiecepath,
		   bool isquiet,
		   string title,
		   bool isverbose,
		   bool keepallbest){
  theRange=r;
  theCons=cs;
  theFocus=focus;
  nestBan=nestbanparam;
  firstMatch=firstmatch;
  isPrimary=isprimary;
  returnFinish=returnfinish;
  theMax=themax;
  keepAllBest=keepallbest;
  atomicVariables=atomicvariables;
  if(theMax)bestMaxValid=true;
  for(auto v:atomicVariables){
    uassert(Atomic::isAtomizable(v),"unexpected non-atomizable variable in passed atomicvariables to path");
    uassert(std::count(atomicVariables.begin(),atomicVariables.end(),v)==1,"unexpected duplicate in atomicVariables");
  }
  if (usepiecepath){
    uassert(theFocus,"PathNode: expected non-null focus with usepiecepath");
    SetBase*startsetnode=theFocus->getSetBase()->clone();
    uassert(startsetnode,"PathNode: missing set from theFocus");
    piecePathNode=new PiecePathNode(startsetnode,new PathLastPositionNode(),false);
  }
  isQuiet=isquiet;
  isVerbose=isverbose;
  theTitle=title;
  for(auto c:theCons)uassert(c,"sbsb");
  conStack.reserve(256);
}

void PathNode::deepify(){
  clonevec(theCons);
  if(hasFocus())theFocus=theFocus->clone();
  if(theMax)theMax=theMax->clone();
  if(piecePathNode)piecePathNode=piecePathNode->clone();
}

/* this is copied from sequencebase.cpp but it is unclear to me why it works
   I assume it is because all the transform operators only act on Node*
   so we instead get the Node children of a SequenceConstituent (in sequencebase).
   So we just get the filters and do not act on the constituents themselves.
   I suppose as long as cloning constituents works OK this should work.
*/
vnode PathNode::children()const{
  vnode v;
  for (PathCon* c:theCons){
    uassert(c && myindex(v,(Node*)c)<0,"PathNode: bad child");
    v.push_back(c);
  }
  if(theFocus){
    uassert(myindex(v,(Node*)theFocus)<0,"PathNode child focus issue");
    v.push_back(theFocus);
  }
  if(theMax){
    uassert(myindex(v,(Node*)theMax)<0,"PathNode child max issue");
    v.push_back(theMax);
  }
  if(piecePathNode){
    uassert(myindex(v,(Node*)piecePathNode)<0,"PathNode child piecepath issue");
    v.push_back(piecePathNode);
  }
    
  return v;
}

int PathNode::ncons()const{
  return (int)(theCons.size());
}

bool PathNode::valid_con (int offset)const{
  uassert(offset>=0,"vcsb");
  return offset<ncons();
}

PathCon* PathNode::getCon(int offset)const{
  uassert(valid_con(offset),"internal in getCon");
  return theCons.at(offset);
};

bool PathNode::match_position(QPos*qpos){
  if (nestBan&&nestSeenPosition(qpos))
    return false;
  theCount=0; // #infocus positions. not sure if count initial
  uassert(conStack.empty(),"lbmp ss empty");
  theStartQPos=qpos;
  currentPosition=qpos;
  conStack=theCons;
  std::reverse(conStack.begin(),conStack.end());
  size_t len=conStack.size();
  bestSoFar=NULL;
  otherBestPositions.clear();
  bestCount=-1;
  bestMax= -100000000;
  bestMaxValid=false;
  initializeComments(qpos);
  if(theFocus)
    theFocus->initialize(theStartQPos);
  int mark=markComments();
  /*the next path is necessary just in case the path body begins with a HolderCon that modifies
    an atomic variable. Such a modification would not be cleared by the standard popAtomicBindings
    because that method is only called when an arrow un moved from*/
  if(hasAtomics())
    pushAtomicBindings();
  compute();
  uassert(len==conStack.size(),"fnmp mismatch");
  uassert(currentPosition==qpos,"lnmp cp mismatch");
  /*the next path is used to undo the affects of the previous pushAtomicBindings(), see above, before the pathnode is evaluated*/
  if(hasAtomics()){
    uassert(atomicBindingStack.size()==1,"lnmatch_position: unexpected nonempty binding stack");
    popAtomicBindings();
  }
  if (!isSuccess()){
    qpos->restoreComments(mark);
    exitMatch();
    return false;
  }
  uassert(bestSoFar,"ln mp internal");
  pushComments();
  notate(qpos,bestSoFar);
  if(otherBestPositions.size())
    for(QPos*otherbest:otherBestPositions){
      notate(qpos,otherbest);
      if(CqlCommentLevel>CommentLevel::Quiet)
	otherbest->appendComment("alternative");
    }
  
  if(nestBan)nestRegisterPositions(qpos,bestSoFar);
  exitMatch();
  return true;
}

void PathNode::notate(QPos*start,QPos*finish){
  if(CqlCommentLevel>CommentLevel::Silent&&hasTitle())
    start->appendComment(getTitle());
  if(CqlCommentLevel>CommentLevel::Silent && piecePathNode){
    string ppnvalue;
    if(piecePathNode->match_stringvalue(start,&ppnvalue)){
      ppnvalue="Focus path: "s + ppnvalue;
      start->appendComment(ppnvalue);
    }
  }

  /*generate per-move comments if Verbose is specified*/
  if(CqlCommentLevel>=CommentLevel::Quiet&&isVerbose){
    vector<QMove*>moves=QPos::pathBetween(start,finish);
    int currcount=0;
    for(QMove*qmove:moves)
      if(!hasFocus()||theFocus->inFocus(qmove)){
	++currcount;
	stringstream s;
	if(hasTitle())
	  s<<getTitle()<<": ";
	s<<"move "<<currcount<<" of " << bestCount;
	qmove->tail->appendComment(s.str());
      }
    uassert(currcount==bestCount,"in generated the output comments pursuant to the 'verbose' option to 'path', a miscount appeared");
  }
  if(CqlCommentLevel<=CommentLevel::Quiet || isQuiet)return;
  uassert(start&&finish,"lbnotate arg");
  int length=bestCount;
  uassert(length>0,"pathnode::notate: unexpected null best count");
  stringstream s;
  s<<"End path of length "<<length<<" that starts at "<<start->idString();
  if(hasMax())
    s<<" Max value: "<<bestMax;
  finish->appendComment(s.str());
  stringstream t;
  t<<"Start path that ends at "<<finish->idString();
  start->appendComment(t.str());
}

void PathNode::exitMatch(){
  commentStack.clear();
  mainStack=NULL;
  conStack.clear();
  if(isSuccess())theStartQPos->qgame->setPathStatus(createPathStatus());
  if(isSuccess()&&hasAtomics())
    applyAtomicBindings(bestAtomicBindings);
  bestAtomicBindings.clear();
  if(theFocus)theFocus->clear();
}

PathStatus PathNode::createPathStatus()const{
  if(bestSoFar){
    uassert(getStartQPos(),"sb css args");
    return PathStatus(getStartQPos(),bestSoFar,bestCount,bestMax);
  }
  return PathStatus();
}


bool PathNode::isSuccess()const{
  /*We do not allow zero-length paths*/
  if (bestSoFar==NULL)return false;
  uassert(bestCount>0,"sB issuccess");
  if(hasMax()){ //keep in sync with !hasmax code below
    uassert(bestMaxValid,"pathnode issuccess no bestmaxvalid");
    return theRange==NULL||
      theRange->valid(bestMax);
  }
  uassert(!hasMax()&&bestSoFar,"lnis eh?");
  return 
    (theRange==NULL ||
     theRange->valid(bestCount));
}

bool PathNode::match_count(QPos*qpos,NumValue*valp){
  uassert(isNumeric()&&qpos&&valp,"lnmc arg");
  if(!match_position(qpos))return false;
  if(hasMax()){ //keep in sync with the !hasMax() below
    uassert(bestMaxValid,"lnmc hmv");
    *valp=bestMax;
    return true;
  }//if hasMax()
  //here hasMax() is false and the match position result was true. keep in sync with hasMax() case above.
  uassert(!hasMax(),"lnmc expected nonhasmax");
  uassert(bestCount>=0,"bad bestCount ln");
  *valp=(NumValue)(bestCount);
  return true;
}


bool PathNode::match_positionvalue(QPos*qpos,QPos**valp){
    uassert(isPosition()&&qpos&&valp,"lnmpv");
  if(match_position(qpos)){
    uassert(bestSoFar!=NULL,"sbmpv bsf");
    *valp=bestSoFar;
    return true;
  }
  return false;
}
void PathNode::mergeSuccess(){
  uassert(theCount>0,"mergeSuccess: 0 count");
  NumValue newmax{-1000000};
  //keep the hasMax() swap code in sync with the not hasMax() code below
  if(hasMax()
     &&getMax()->match_count(currentPosition,&newmax)){

    if(newmax>bestMax){
      bestMax=newmax;
      bestMaxValid=true;
      bestCount=theCount;
      bestSoFar=currentPosition;
      otherBestPositions.clear();
      if(hasAtomics())
	bestAtomicBindings=createAtomicBindings();
      swapComments(currentPosition,true);
    }
    else if (newmax==bestMax&&keepAllBest){
      otherBestPositions.push_back(currentPosition);
      swapComments(currentPosition,false);
    }
  } //if hasMax() and newmax >= oldmax
  if (hasMax()) return;
  if (theCount>bestCount){          //keep in sync with the if hasMax() code above
    bestCount=theCount;
    bestSoFar=currentPosition;
    otherBestPositions.clear();
    if(hasAtomics())
      bestAtomicBindings=createAtomicBindings();
    swapComments(currentPosition,true);
  }
  else if (theCount==bestCount&&keepAllBest){
    otherBestPositions.push_back(currentPosition);
    swapComments(currentPosition,false);
  }
}
