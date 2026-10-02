#include "dictionaryaccessnode.h"
DictionaryRetrieveNode::DictionaryRetrieveNode(Dictionary*d,Node*key):
  DictionaryAccessNode(d,key){
  uassert(theDictionary&&theKey,"drn retrieve bad args");
  theDictionary->verifyKey(theKey);
}

bool DictionaryRetrieveNode::match_position(QPos*qpos){
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if (AnyValue::isFalse(keyvalue))return false;
  return theDictionary->hasKey(keyvalue);
}

bool DictionaryRetrieveNode::match_stringvalue(QPos*qpos,string*valp){
  uassert(qpos&&valp,"drnsv");
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if(AnyValue::isFalse(keyvalue))return false;
  Any result;
  if(!theDictionary->getValue(keyvalue,&result))
    return false;
  uassert(AnyValue::isString(result),"When attempting to retrieve value from dictionary, got a non-string when expecting a string");
  *valp=AnyValue::stringValue(result);
  return true;
}

bool DictionaryRetrieveNode::match_positionvalue(QPos*qpos,QPos**valp){
  uassert(qpos&&valp,"drnsv");
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if(AnyValue::isFalse(keyvalue))return false;
  Any result;
  if(!theDictionary->getValue(keyvalue,&result))
    return false;
  uassert(AnyValue::isQPos(result),"When attempting to retrieve value from dictionary, got a non-position when expecting a position");
  *valp=AnyValue::qPosValue(result);
  return true;
}

bool DictionaryRetrieveNode::match_count(QPos*qpos,NumValue*valp){
  uassert(qpos&&valp,"drnsv");
  Any keyvalue=AnyValue::eval(theKey,qpos);
  if(AnyValue::isFalse(keyvalue))return false;
  Any result;
  if(!theDictionary->getValue(keyvalue,&result))
    return false;
  uassert(AnyValue::isNumValue(result),"When attempting to retrieve value from dictionary, got a non-position when expecting a number");
  *valp=AnyValue::numValue(result);
  return true;
}

SquareMask DictionaryRetrieveNode::getSquares(QPos*qpos){
  uassert(qpos,"drnsv");
  Any keyvalue=AnyValue::eval(theKey,qpos);
  SquareMask ret;
  if(AnyValue::isFalse(keyvalue))return ret;
  Any result;
  if(!theDictionary->getValue(keyvalue,&result))
    return ret;
  uassert(AnyValue::isSquareMask(result),"When attempting to retrieve value from dictionary, got a non-position when expecting a set");
  return AnyValue::squareMaskValue(result);
}

bool DictionaryRetrieveNode::isNumeric()const{
  return theDictionary->isNumericValue();
}

bool DictionaryRetrieveNode::isString()const{
  return theDictionary->isStringValue();
}

bool DictionaryRetrieveNode::isPosition()const{
  return theDictionary->isPositionValue();
}

bool DictionaryRetrieveNode::isSet()const{
  return theDictionary->isSetValue();
}




