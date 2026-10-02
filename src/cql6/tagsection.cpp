#include "tagsection.h"
#include "cqlglobals.h"
#include "cql.h"
#include "qgame.h"
#include "markboard.h"
const vector<string> TagSection::unchangeableTagNames{
  "Black",
    "BlackBCF",
    "BlackDWZ",
    "BlackElo",
    "BlackICCF",
    "BlackRapid",
    "BlackRating",
    "BlackUSCF",
    "Date",
    "ECO",
    "EventDate",
    "FEN",
    "Result",
    "Round",
    "Site",
    "White",
    "WhiteBCF",
    "WhiteDWZ",
    "WhiteElo",
    "WhiteICCF",
    "WhiteRapid",
    "WhiteRating",
    "WhiteUSCF",
    "Event",
    };    
    
void TagSection::initialize(QGame*qgame){
  theEntries.clear();
  isInitialized=false;
  Game *game=qgame->game;
  tagT* gametags=game->GetExtraTags();
  int gamenumtags=(int)(game->GetNumExtraTags());
  for (int tagi=0;tagi<gamenumtags;++tagi){
    char*gametagname=gametags[tagi].tag;
    char*gametagvalue=gametags[tagi].value;
    if (!gametagname||!gametagvalue)continue;
    theEntries.push_back(TagEntry(gametagname,gametagvalue,true));
  }
  isInitialized=true;
}

bool TagSection::isForbiddenName(const string& name){
  return myindex(unchangeableTagNames,name)>=0;
};

bool TagSection::exists(const string& name)const{
  for (const TagEntry& entry : theEntries)
    if(entry.getName()==name)return true;
  return false;
}

bool TagSection::getGameValue(const string&name, string*valuep)const{
  for (const TagEntry& entry: theEntries)
    if(entry.getName()==name&&entry.isFromGame){
      if (valuep) *valuep=entry.getGameValue();
      return true;
    }
  return false;
}

void TagSection::setValue(const string&name, const string&value){
  for(TagEntry& entry : theEntries)
    if (entry.getName()==name){
      entry.setValue(value);
      return;
    }
  theEntries.push_back(TagEntry(name,value,false));
}

void TagSection::merge(QGame*qgame){
  uassert(isInitialized,"tsm merge");
  Game*game=qgame->game;
  uassert(game,"ts merge game");
  for (const TagEntry&entry:theEntries)
    if (entry.isModified)
      MarkBoard::setNonstandardTag(game, entry.getName(), entry.getValue());
}

	
