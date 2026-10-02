#include "hhdbkeyword.h"
#include "util.h"
#include <sstream>
bool HhdbKeyword::isIn(const vector<string>& v, const string&k){
  return myindex(v,k)>=0;
}

bool HhdbKeyword::isPlayerBlackKey(const string &key){
  return isIn(playerBlackKeys,key);
}
bool HhdbKeyword::isAwardKey(const string &key){
  return isIn(awardKeys,key);
}
bool HhdbKeyword::isOtherKey(const string &key){
  return isIn(otherKeys,key);
}
bool HhdbKeyword::isAwardTypeKey(const string&key){
  return isIn(awardTypeKeys,key);
}

bool HhdbKeyword::isKey(const string& key){
  return isPlayerBlackKey(key)||
    isAwardKey(key)||
    isOtherKey(key)||
    isGbrKey(key)||
    isAbbreviation(key);
}

bool HhdbKeyword::isGbrKey(const string&key){
  return isIn(gbrKeys,key);
}

bool HhdbKeyword::isAbbreviation(const string& key){
  return matchAbbreviation(key).size();
}
string HhdbKeyword::matchAbbreviation(const string &abbreviation){
  for(const pair<string,string> & soughtpair:abbreviationMap)
    if(soughtpair.first==abbreviation)
      return soughtpair.second;
  return "";
}

vector<string>HhdbKeyword::allKeys(){
  vector<string>ret;
  for (string key: playerBlackKeys)
    ret.push_back(key);
  for (string key:awardKeys)
    ret.push_back(key);
  for (string key:otherKeys)
    ret.push_back(key);
  for (pair<string,string> entry:abbreviationMap)
    ret.push_back(entry.first);
  std::stable_sort(ret.begin(),ret.end());
  return ret;
}

string HhdbKeyword::showKeys(){
  vector<string>keys=allKeys();
  stringstream s;
  int width=0;
  for (string key:keys){
    if(width+key.size()+1>60){ //Chosen because gmail word wraps at 70 characters
      width=0;
      s<<endl;
    }
    s<<key<<' ';
    width+= key.size()+1;

  }
  if(width>0) s<<endl;
  return s.str();
}

bool HhdbKeyword::takesParameterKey(const string&key){
  return isIn(takesParameterKeys,key);
}

bool HhdbKeyword::isQuotedKey(const string&key){
  if(!isKey(key))return false;
  for(char c: key)
    if (!(c>='0'&&c<='9'||
	  c>='a'&&c<='z'||
	  c>='A'&&c<='Z'||
	  c=='_')) return true;
  return false;
}
	
    
  

