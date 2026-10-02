#include "dictionaryaccessnode.h"
DictionaryIterateNode::DictionaryIterateNode(Dictionary*d,Variable*v,Node*body):DictionaryAccessNode(d,NULL,NULL,body,v){
  uassert(theDictionary&&theVariable&&theBody,"drn iterate bad args");
  auto keytype=theDictionary->keyType;
  uassert(keytype!=ValueType::None,"DIN: key type not yet set");
  auto vartype=theVariable->valuetype();
  uassert(keytype==vartype,"DictionaryIterateNode: bad variable type or unset dictionary key type");
}

bool DictionaryIterateNode::match_position(QPos*qpos){
  auto keytype=theDictionary->keyType;
  uassert(keytype!=ValueType::None,"DIN: key type not yet set");
  auto vartype=theVariable->valuetype();
  uassert(keytype==vartype,"DictionaryIterateNode: bad variable type or unset dictionary key type");
  if(theVariable->isBound()){
    stringstream s;
    string name=theVariable->name;
    s<<"when attempting to evaluate a dictionary iterator of the form\n"
     <<"    [type] "<<name<< " in (" <<theDictionary->name<<")...\n"
     <<" the variable "<<name<<" is already bound. This might indicate user error, since the previous value of "<<name<< " would be overwritten";
    eassert(false,s.str());
  }
  for (auto &entry: theDictionary->getMap()){
    theVariable->assignAny(entry.first);
    theBody->match_position(qpos);
  }
  theVariable->unbind();
  return true;
}



