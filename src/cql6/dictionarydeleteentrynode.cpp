#include "dictionaryaccessnode.h"
DictionaryDeleteEntryNode::DictionaryDeleteEntryNode(Dictionary*d,Node*key):DictionaryAccessNode(d,key){
  uassert(theDictionary&&theKey,"drn delete entry bad args");
  theDictionary->verifyKey(theKey);
}

bool DictionaryDeleteEntryNode::match_position(QPos*qpos){
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if (AnyValue::isFalse(keyvalue))return false;
  theDictionary->deleteKey(keyvalue);
  return true;
}




