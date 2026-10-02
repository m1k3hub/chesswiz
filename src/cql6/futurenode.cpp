#include "node.h"
#include "futurenode.h"

FutureNode::FutureNode(vector<SeqConstituent*>cs,Range*r,bool isskip,bool nestban,bool firstmatch, bool isprimary, bool issecondary,bool returnfinish, bool isquiet):SequenceBase(cs,r,isskip,nestban,firstmatch,isprimary,issecondary,returnfinish,isquiet){
}

void FutureNode::compute(HolderConstituent*holder,QPos*qpos){
  if (firstMatch && bestSoFar) return; //added for 9.224 by stiller Gamble bug 9/21/2020. Stop unnecessary evaluation of filter with side effects. Cross-ref computeLinearize()
  int mark=markComments();
  uassert(qpos,"FutureNode::compute: qpos");
  size_t stacklen=seqStack.size();
  uassert(holder,"fncholdererr");
  Node*filter=holder->filter;
  uassert(filter,"fncfilter");
  if (!CqlDoNotLinearize && !filter->linearize()->empty()) 
    return computeLinearize(holder,qpos);
  if(!filter->match_position(qpos))
    {restoreComments(mark);
      return;}

  if(computeNull()&&!skipCurrentPosition(qpos)){
    mergeSuccess(qpos);
  }
  if(seqStack.empty() || qpos->terminal()){
    restoreComments(mark);// we actually only need to do this if there is no mergeSuccess();
    return;} 

  //This position matches the filter but there are more stack constituents and children to consider
  
  for(auto child:qpos->children)
    if(isPrimary&&child->getSiblingIndex()>0 ||
       isSecondary&&child->getSiblingIndex()==0)
      continue;
  else
    SequenceBase::compute(child); //Why do I need the class qualifier?
  uassert(seqStack.size()==stacklen,"fnch size");
  restoreComments(mark);
  return;
  }

