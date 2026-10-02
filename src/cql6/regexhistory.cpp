#include "regexhistory.h"
/* This relies on the fact that an unmatched group will be an empty string*/

void RegexHistory::registerMatch(const std::smatch&matchresult){
  clear();
  int ngroups=(int)(matchresult.size());
  uassert(ngroups>0 && matchresult[0].matched,"RegexHistory: cannot register unmatched regex");
  for(int i=0;i<ngroups;++i){
    bool matched=matchresult[i].matched;
    if (matched){
      groupStrings.push_back(matchresult[i]);
      groupStarts.push_back(matchresult.position(i));
      groupMatched.push_back(true);
    }
    else{
      groupStrings.push_back("");
      groupStarts.push_back(0);
      groupMatched.push_back(false);
    }
  }//for(i=0;i<ngroups;i++)
}

int RegexHistory::getNgroups()const{
  return (int)(groupStrings.size());
}

/*this should only ever be called with a valid group*/
bool RegexHistory::groupString(int group,string*resultp)const{
  uassert(group>=0,"regexhistory: invalid group value");
  if (group>=getNgroups()){
    stringstream s;
    s<<"Illegal group value. The group numbered "<<group
     <<" was requested but the last regex search only had "
     <<getNgroups()
     <<" in it ";
    eassert(false,s.str());
  }
  if (!groupMatched.at(group))return false;
  if(resultp) *resultp=groupStrings.at(group);
  return true;
}

/*this should only ever be called with a valid group!*/
int RegexHistory::groupStart(int group)const{
  if (group>=getNgroups()){
    stringstream s;
    s<<"Attempt to access regex group number: "
     <<group<< " for its location, but the last matching regex group only had "<< getNgroups()<< " groups";
    eassert(false,s.str());
  }
  if (groupMatched.at(group))
    return groupStarts.at(group);
  else return -1;
}

void RegexHistory::clear(){
  groupStrings.clear();
  groupStarts.clear();
  groupMatched.clear();
}

string RegexHistory::toString()const{
  stringstream s;
  s<<"<RegexHistory: ngroups: "<<getNgroups();
  for (int i=0;i<getNgroups();++i)
    s<<"\n\tgroup#"<<i
     <<"@"<<groupStarts[i]
     <<": "
     <<groupStrings[i];
  return s.str();
}
    

  

  


  
