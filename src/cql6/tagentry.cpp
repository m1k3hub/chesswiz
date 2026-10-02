#include "tagentry.h"
#include "node.h"
TagEntry::TagEntry(const string& name,
		   const string&value,
		   bool isfromgame):theName(name),
					  theValue(value),
					  isFromGame(isfromgame)
{
  uassert(theName.size(),"Cannot create tag with empty name");
  if (!isFromGame) isModified=true;
  else gameValue=theValue;
  //check for valid name here
}
string TagEntry::toString()const{
  stringstream s;
  string valstring;
  if (isDeleted)
    valstring="DELETED";
  else if (isModified)
    valstring=theValue;
  else {
    uassert(isFromGame,"TagEntry: entry issue for: ", theName);
    valstring=gameValue;
  }
      
  s<<"["<<theName
   <<' '
   <<"\""
   <<theValue
   <<"\""
   <<']';
  return s.str();
}


void TagEntry::setValue(const string& value){
  theValue=value;
  isModified=true;
  isDeleted=false;
}


string TagEntry::getGameValue()const{
  uassert(isFromGame,"getGameValue: not from game");
  return gameValue;
}
