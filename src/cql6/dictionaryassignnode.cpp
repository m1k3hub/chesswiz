#include "dictionaryaccessnode.h"
DictionaryAssignNode::DictionaryAssignNode(Dictionary*d,Node*key,Node*value):DictionaryAccessNode(d,key,value){
  uassert(theDictionary&&theKey&&theValue,"drn assign bad args");
  theDictionary->verifyKey(theKey);
  theDictionary->verifyValue(theValue);
}

bool DictionaryAssignNode::match_position(QPos*qpos){
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if (AnyValue::isFalse(keyvalue))return false;
  Any valuevalue=AnyValue::eval(theValue,qpos);
  if(AnyValue::isFalse(valuevalue))return false;
  theDictionary->assignValue(keyvalue,valuevalue);
  return true;
}



