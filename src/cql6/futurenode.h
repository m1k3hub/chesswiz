#pragma once
#include "sequencebase.h"
class FutureNode : public SequenceBase{
 public:
  bool isFuture(){return true;}
  bool isPast(){return false;}
  void computeLinearize(HolderConstituent*,QPos*);
  void compute(HolderConstituent*,QPos*qpos);
  string thisclass()const{return "FutureNode";}
[[nodiscard]]  FutureNode*clone();
  FutureNode(vector<SeqConstituent*>,Range*,bool isskip, bool nestban, bool firstmatch,bool isprimary, bool issecondary,bool returnfinish, bool isquiet);
  SeqDir getSearchDirection(){return SeqDir::Future;}
};
