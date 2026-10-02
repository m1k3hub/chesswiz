#include "dictionaryaccessnode.h"

DictionaryAccessNode::DictionaryAccessNode(Dictionary*d,
					   Node*key,
					   Node*value,
					   Node*body,
					   Variable*v):
  theDictionary(d),
  theKey(key),
  theValue(value),
  theBody(body),
  theVariable(v)
{
  uassert(d,"null dictionary to dictionaryaccessnode");
}

SquareMask DictionaryAccessNode::getSquares(QPos* qpos){
  uassert(false,"DictionaryAccessNode getSquares() method was called, but should never be.");
  return SquareMask();
}

vnode DictionaryAccessNode::children()const{
  vnode ret;
  uassert(theDictionary,"dan children dictionary");
  ret.push_back(theDictionary);
  if(theKey)myinsert(ret,theKey);
  if(theBody)myinsert(ret,theBody);
  if(theValue)myinsert(ret,theValue);
  if(theVariable)myinsert(ret,(Node*)theVariable);
  return ret;
}

void DictionaryAccessNode::deepify(){
  if(theDictionary)theDictionary=theDictionary->clone();//not needed
  if(theKey)theKey=theKey->clone();
  if(theBody)theBody=theBody->clone();
  if(theValue)theValue=theValue->clone();
  if(theVariable)theVariable=theVariable->clone();//not needed
 }
  
  
