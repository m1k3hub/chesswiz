#include "dictionaryaccessnode.h"
DictionaryDeleteDictionaryNode::DictionaryDeleteDictionaryNode(Dictionary*d):DictionaryAccessNode(d){
}

bool DictionaryDeleteDictionaryNode::match_position(QPos*qpos){
  theDictionary->clear();
  return true;
}




