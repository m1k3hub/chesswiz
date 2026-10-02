#include "sequencebase.h"

void RepeatConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}

void StarConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}

void PlusConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}

void VectorConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}



void HolderConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}

void OptionalConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}

void RepeatInProcessConstituent::compute(SequenceBase*base,QPos*qpos){
  base->compute(this,qpos);
}
