#include "node.h"
#include "sequencebase.h"
#include "tomovenode.h"

bool seqdir_valid(SeqDir s){
  return s==SeqDir::Past||s==SeqDir::Future;
}

vnode SequenceBase::children()const{
  vnode v;
  for (SeqConstituent* c:constituents)
    for (Node* child:c->children()){
      uassert(c,"sbc int");
      uassert(myindex(v,child)<0,"unexpected duplicate child");
      v.push_back(child);
    }
  // Do NOT include the skipholders here because they will transform under flipcolor, which we do NOT want
  return v;
}
SequenceBase::SequenceBase(vector<SeqConstituent*>cs,Range*r,bool isskip,bool nestbanparam,bool firstmatch,bool isprimary, bool issecondary, bool returnfinish,bool isquiet){
  range=r;
  constituents=cs;
  nestBan=nestbanparam;
  firstMatch=firstmatch;
  isPrimary=isprimary;
  isSecondary=issecondary;
  returnFinish=returnfinish;
  isQuiet=isquiet;
  uassert(isPrimary+isSecondary<=1,"Sb isprimary args");
  for(auto c:constituents)uassert(c,"sbsb");
  if (isskip) {
    theWhiteHolder=new HolderConstituent(new ToMoveNode(WHITE));
    theBlackHolder=new HolderConstituent(new ToMoveNode(BLACK));
  }
  seqStack.reserve(256);
}

bool SequenceBase::valid_constituent (int offset)const{
  uassert(offset>=0,"vcsb");
  return offset<nconstituents();
}

SeqConstituent* SequenceBase::getConstituent (int offset)const{
  uassert(valid_constituent(offset),"internal in getConstituent");
  return constituents.at(offset);
};

int SequenceBase::nconstituents()const{
  return (int)(constituents.size());
}


bool SequenceBase::match_position(QPos*qpos){
  if (nestBan&&nestSeenPosition(qpos))
    return false;
  if(isSkip()) initializeSkip(qpos);
  count=-1;
  uassert(seqStack.empty(),"sbmp ss empty");
  seqStack=constituents;
  std::reverse(seqStack.begin(),seqStack.end());
  size_t len=seqStack.size();
  bestSoFar=NULL;
  initializeComments(qpos);
  int mark=markComments();
  compute(qpos);
  uassert(len=seqStack.size(),"fnmp mismatch");
  if(isFalse()){
    qpos->restoreComments(mark);
    exitMatch();
    return false;}
  uassert(bestSoFar,"sb mp internal");
  count=qpos->getPly()-bestSoFar->getPly();
  if(count<0)count= -count;
  count++;
  if (isSkip()) count=(count+1)/2;
  if(range&&!range->valid(count)) {exitMatch();return false;}
  pushComments();
  notate(qpos,bestSoFar);
  if(nestBan)nestRegisterPositions(qpos,bestSoFar);
  exitMatch();
  return true;
}

void SequenceBase::exitMatch(){
  commentStack.clear();
  mainStack=NULL;
  if(isSkip()){
    uassert(theSkipColor!=NOCOLOR,"sbem s");
    theSkipColor=NOCOLOR;
  }
  seqStack.clear();
}

void SequenceBase::compute(QPos*qpos){
  if(seqStack.empty())return;
  if(firstMatch&&bestSoFar)return;
  if(skipCurrentPosition(qpos))
    return computeSkip(qpos);
  size_t startlen=seqStack.size();
  SeqConstituent*top=seqStack.back();
  seqStack.pop_back();
  top->compute(this,qpos);
  seqStack.push_back(top);
  uassert(seqStack.size()==startlen,"bad stacksize fncmain");
}

void SequenceBase::compute(RepeatConstituent*repeat,QPos*qpos){
  size_t stacklen=seqStack.size();
  RepeatInProcessConstituent rprocess(repeat);
  seqStack.push_back(&rprocess);
  compute(qpos);
  uassert(seqStack.size()==stacklen+1,"SequenceBase: compute RepeatConstituent: stack");
  seqStack.pop_back();
  uassert(seqStack.size()==stacklen,"sbrc stack");
}

void SequenceBase::compute(RepeatInProcessConstituent*rprocess,QPos*qpos){
  int min=rprocess->min();  //min allowed matches
  int max=rprocess->max();  //max allowed matches
  int nseen=rprocess->nSeen; // number of constituents pushed on the stack by this method so far
  size_t stacklen=seqStack.size();
  SeqConstituent*c=rprocess->getConstituent(); //constituent to be repeated
  uassert(min>=0&&nseen<=max,"sbcrpc minmax");
  if(nseen>=min&&nseen<=max) //if we have seen enough to be ok then match what is left
    compute(qpos);
  if(nseen<max){             //if we might benefit by trying a new constituent?
    seqStack.push_back(rprocess);  // (this follows compute(StarConstituent*...)
    seqStack.push_back(c);     // push a new constituent
    rprocess->nSeen++;        // and tell the RepeatInProcessConstituent on the stack it has seen another
    compute(qpos);            // and try again.
    uassert(seqStack.size()==stacklen+2,"sbc rpc stack");
    uassert(rprocess->nSeen==nseen+1,"sbc rpc nseen");
    rprocess->nSeen--;
    seqStack.pop_back();
    seqStack.pop_back();
  }
  uassert(seqStack.size()==stacklen,"sbc rpc stack2");
  uassert(rprocess->nSeen==nseen,"sbc rpc nseen2");
}
    
void SequenceBase::compute(StarConstituent*star,QPos*qpos){
  compute(qpos); //empty
  SeqConstituent*c=star->constituent;
  size_t seqstacklen=seqStack.size();
  seqStack.push_back(star);
  seqStack.push_back(c);
  compute(qpos);
  uassert(seqStack.size()==seqstacklen+2,"sbcompute seqstacklen star");
  seqStack.pop_back();
  seqStack.pop_back();
  uassert(seqStack.size()==seqstacklen,"sbcompute seqstacklen star 2");
}

void SequenceBase::compute(PlusConstituent*plus,QPos*qpos){
  StarConstituent*star=plus->getStarConstituent();
  SeqConstituent*c=star->constituent;
  size_t seqstacklen=seqStack.size();
  seqStack.push_back(star);
  seqStack.push_back(c);

  compute(qpos);
  uassert(seqStack.size()==seqstacklen+2,"sb compute plus stack");
  seqStack.pop_back();
  seqStack.pop_back();
  uassert(seqStack.size()==seqstacklen,"sb compute plus seqStack 2");

}

void SequenceBase::compute(OptionalConstituent*optional,QPos*qpos){
  SeqConstituent*c=optional->constituent;
  size_t seqstacklen=seqStack.size();
  compute(qpos);
  uassert(seqstacklen==seqStack.size(),"fncoclen");
  seqStack.push_back(c);
  compute(qpos);
  uassert(seqStack.size()==seqstacklen+1,"sb compute ? seqStacksize");
  seqStack.pop_back();
  uassert(seqStack.size()==seqstacklen,"sb compute ? seqStacksize 2");

}

void SequenceBase::compute(VectorConstituent*vc,QPos*qpos){
  size_t seqstacklen=seqStack.size();
  uassert(vc,"fncvc");
  vector<SeqConstituent*>&v=vc->constituents;
  int nconstituents=(int)(v.size());
  uassert(nconstituents,"fncvc");
  for(int i=nconstituents-1;i>=0;--i)
    seqStack.push_back(v.at(i));
  uassert(seqStack.size()==seqstacklen+nconstituents,"fnclen");
  compute(qpos);
  uassert(seqStack.size()==seqstacklen+nconstituents,"fnclen");
  for(int i=0;i<nconstituents;++i)
    seqStack.pop_back();
  uassert(seqStack.size()==seqstacklen,"fnclen3");

}

bool SequenceBase::computeNull(){
  for(auto p : seqStack)
    if(!p->matchesNull())return false;
  return true;
}

void SequenceBase::deepify(){
  clonevec(constituents); // VERY IMPORTANT!!!
  // The next two lines are essentially optional but included for consistency
  if(theWhiteHolder)theWhiteHolder=theWhiteHolder->clone();
  if(theBlackHolder)theBlackHolder=theBlackHolder->clone();
}
/********SKIP METHODS**************/

void SequenceBase::initializeSkip(QPos*qpos){
  uassert(qpos,"sbis");
  colorT tomove=qpos->getToMove();
  uassert(tomove==WHITE||tomove==BLACK,"sbist");
  if (tomove==WHITE)
    setSkipColor(BLACK);
  else if (tomove==BLACK)
    setSkipColor(WHITE);
}

void SequenceBase::computeSkip(QPos*qpos){
  uassert(isSkip()&&skipCurrentPosition(qpos),"computeSkip internal");
  HolderConstituent*skipconstituent=getSkipConstituent();
  return compute(skipconstituent,qpos);
}


HolderConstituent*SequenceBase::getSkipConstituent()const{
  colorT c=getSkipColor();
  HolderConstituent* ret=NULL;
  switch(c){
  case WHITE:ret=theWhiteHolder;break;
  case BLACK:ret=theBlackHolder;break;
  default: uassert(false,"hcgsh: internal");
  }
  uassert(ret,"getskipholder: internal");
  return ret;
}

bool SequenceBase::isSkip()const{
  return theWhiteHolder!=NULL;
}

colorT SequenceBase::getSkipColor()const{
  uassert(isSkip(),"sbgsc");
  colorT ret=theSkipColor;
  uassert(ret==WHITE||ret==BLACK,"sb skipcolor color");
  return ret;
}

bool SequenceBase::skipColor(colorT c)const{
  uassert(isSkip()&&c==WHITE||c==BLACK,"sbsc");
  return getSkipColor()==c;
}

void SequenceBase::clearSkipColor(){
  uassert(isSkip(),"sbcsc");
  uassert(theSkipColor==WHITE||theSkipColor==BLACK,"sbcsc col");
  theSkipColor=NOCOLOR;
}

void SequenceBase::setSkipColor(colorT c){
  uassert(isSkip()&&(c==WHITE||c==BLACK),"sbssc");
  uassert(theSkipColor==NOCOLOR,"sbssc nc");
  theSkipColor=c;
}

bool SequenceBase::skipCurrentPosition(QPos*qpos)const{
  if(!isSkip())return false;
  colorT tomove=qpos->getToMove();
  uassert(tomove==WHITE||tomove==BLACK,"sbscp");
  return skipColor(tomove);
}


bool SequenceBase::match_positionvalue(QPos*qpos,QPos**positionp){
  uassert(isPosition()&&qpos&&positionp,"sbmpv");
  if(match_position(qpos)){
    uassert(bestSoFar!=NULL,"sbmpv bsf");
    *positionp=bestSoFar;
    return true;
  }
  return false;
}

bool SequenceBase::match_count(QPos*qpos, NumValue*value){
  uassert(isNumeric()&&qpos&&value,"sbmc arg");
  if (match_position(qpos)){
    uassert (count>=0,"match_count");
    *value=(NumValue)(count);
    return true;
  }
  return false;
}
    
void SequenceBase::notate(QPos*start,QPos*finish){
  if(CqlCommentLevel<=CommentLevel::Quiet || isQuiet)return;
  uassert(start&&finish,"sbnotate arg");
  if(isSkip())uassert(start->toMove==finish->toMove,"sequencebase::notate: skip color mismatch");
  /* The next three lines fix bug CQLI9.186-1 where length was wrong if isPast()
     (fixed in build 9.189, bug found by Lionel 5/23/2019)*/
  int length=finish->getPly()-start->getPly();
  if(isPast())length= -length;
  length++;
  uassert(length>0,"SequenceBase::notate length");
  if (isSkip()) length= (length+1)/2;
  stringstream s;
  s<<"End line of length "<<length<<" that starts at "<<start->idString();
  finish->appendComment(s.str());
  stringstream t;
  t<<"Start line that ends at "<<finish->idString();
  start->appendComment(t.str());
}

bool SequenceBase::isNumeric()const{
  return !returnFinish;
}

bool SequenceBase::isPosition()const{
  return returnFinish;
}

bool SequenceBase::isFalse(){
  return bestSoFar==NULL;
}

bool SequenceBase::isTrue(){
  return bestSoFar!=NULL;
}
