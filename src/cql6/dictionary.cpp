#include "dictionary.h"


bool Dictionary::match_position(QPos* qpos){
  return true;
}

Dictionary::Dictionary(string nm, bool ispersistent){
  name=nm;
  if (ispersistent){
    setPersistent();
    uassert(isPersistent(),"dictionary internal ispersistent construct");
  }
  bound=true;
  uassert(name.size(),"dnvnv nm");
}

void Dictionary::deleteKey(const Any&key){
  theMap.erase(key);
}

int Dictionary::count()const{
  return (int)theMap.size();
}

void Dictionary::clear(){
  theMap.clear();
}

string Dictionary::toString(){
  stringstream s;
  s<<"Dictionary "<<name<<" with "<<count()<<" entries: "<<endl;
  for (const std::pair<const Any,Any> &entry : theMap)
    s<<AnyValue::toString(entry.first)<<": "<<AnyValue::toString(entry.second)<<endl;
  return s.str();
}
    
bool Dictionary::hasKey(const Any&key)const{
  return theMap.count(key)>0;
}

void Dictionary::assignValue(const Any&key, const Any& value){
  theMap[key]=value;
}

bool Dictionary::getValue(const Any&key,Any* valuep)const{
  if (!hasKey(key)) return false;
  if (valuep)
    *valuep=theMap.at(key);
  return true;
}

vector<Any>Dictionary::getKeys()const{
  vector<Any>ret;
  for(auto entry:theMap)
    ret.push_back(entry.first);
  return ret;
}
  
bool Dictionary::verifyKey(Node*key){
  uassert(key,"dictionary vk key");
  if(keyType==ValueType::None){
    keyType=key->valuetype();
    uassert(keyType!=ValueType::None&&
	    keyType!=ValueType::Logical,"vk: cannot get key type");
    return true;
  }
  return keyType==key->valuetype();
}

bool Dictionary::verifyValue(Node*value){
  uassert(value,"dictionary vk value");
  if(valueType==ValueType::None){
    valueType=value->valuetype();
    uassert(valueType!=ValueType::None&&
	    valueType!=ValueType::Logical,"vk: cannot get value type");
    return true;
  }
  return valueType==value->valuetype();
}

bool Dictionary::isNumericValue()const{
  return valueType==ValueType::Number;
}

bool Dictionary::isSetValue()const{
  return valueType==ValueType::Set;
}

bool Dictionary::isStringValue()const{
  return valueType==ValueType::String;
}
  

bool Dictionary::isPositionValue()const{
  return valueType==ValueType::Position;
}


void Dictionary::setTypes(ValueType v1,ValueType v2){
  uassert(v1!=ValueType::None&&v2!=ValueType::None,"dictionary::settypes bad type");
  if(keyType!=ValueType::None)
    uassert(keyType==v1,"in dictionary::settypes: key type mismatch");
  if(valueType!=ValueType::None)
    uassert(valueType==v2,"in dictionary::settypes: key type mismatch");
  keyType=v1;
  valueType=v2;
}


void Dictionary::reset(){
  uassert(!isPersistent(),"attempt to reset a peristent dictionary");
  clear();
}
