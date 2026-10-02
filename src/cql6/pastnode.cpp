#include "pastnode.h"

PastNode::PastNode(vector<SeqConstituent*>cs,Range*r,bool isskip, bool nestban,bool firstmatch,bool isprimary,bool issecondary,bool returnfinish,bool isquiet):SequenceBase(cs,r,isskip,nestban,firstmatch,isprimary,issecondary,returnfinish,isquiet){
  uassert(!isprimary&&!issecondary,"primary/secondary specifier with line<--");
}

void PastNode::compute(HolderConstituent*holder,QPos*qpos){
  if (firstMatch && bestSoFar) return; /*added for 9.225 by stiller Gamble bug 9/21/2020. 
                                        Stop unnecessary evaluation of filter with side effects. 
                                        This is not actually necessary here almost certainly 
                                        but is included for simplicity by analogy with futurenode.cpp::FutureNode::compute*/
  int mark=markComments();
  size_t stacklen=seqStack.size();
  uassert(holder,"fncholdererr");
  Node*filter=holder->filter;
  uassert(filter,"fncfilter");
  if(!filter->match_position(qpos)){
    restoreComments(mark);
    return;
  }
  /*the skipposition() test was added 12/1/2019 by 
    stiller to fix singlecolor backward 
    bug reported by Gamble*/
  if(computeNull()&&!skipCurrentPosition(qpos)){ 
    mergeSuccess(qpos);
  }
  if(seqStack.empty() || qpos->initial()){restoreComments(mark);return;}
		       
  if(qpos->initial()){restoreComments(mark);return;}
  SequenceBase::compute(qpos->parent);
  uassert(seqStack.size()==stacklen,"fnch size");
  restoreComments(mark);
}

