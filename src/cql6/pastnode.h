#pragma once
#include "sequencebase.h"
class PastNode : public SequenceBase{
 public:
  bool isFuture(){return false;}
  bool isPast(){return true;}
  void compute(HolderConstituent*,QPos*qpos);
  string thisclass()const{return "PastNode";}
[[nodiscard]]  PastNode*clone();
  PastNode(vector<SeqConstituent*>,Range*,bool isskip, bool nestban, bool firstmatch,bool isprimary,bool issecondary,bool returnfinish,bool isquiet);
  SeqDir getSearchDirection(){return SeqDir::Past;}
};
