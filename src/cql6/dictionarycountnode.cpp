#include "dictionaryaccessnode.h"
DictionaryCountNode::DictionaryCountNode(Dictionary*d):DictionaryAccessNode(d){
}

bool DictionaryCountNode::match_position(QPos*qpos){
  eassert(false,"Attempt to count the elements of a dictionary, but the value is never used. Although legal, this is likely due to user error.");
  return true;
}

bool DictionaryCountNode::match_count(QPos*qpos,NumValue*valp){
  if(valp)
    *valp=(NumValue)(theDictionary->count());
  return true;
}





