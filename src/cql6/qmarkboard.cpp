#include "markboard.h"
#include "abbreviations.h"
#include "qmarkboard.h"
#include "qgame.h"

string QMarkBoard::getECO(QGame*qgame){
  return MarkBoard::getECO(qgame->game);
}

string QMarkBoard::getDate(QGame*qgame){
  return MarkBoard::getDate(qgame->game);
}

string QMarkBoard::getEventDate(QGame*qgame){
  return MarkBoard::getEventDate(qgame->game);
}

string QMarkBoard::getEvent(QGame*qgame){
  return MarkBoard::getEvent(qgame->game);
}

string QMarkBoard::getPlayer(QGame*qgame,colorT color){
  return MarkBoard::getPlayer(qgame->game,color);
}
int QMarkBoard::getElo(QGame*qgame,colorT color){
  return MarkBoard::getElo(qgame->game,color);
}
string QMarkBoard::getSite(QGame*qgame){
  return MarkBoard::getSite(qgame->game);
}

string QMarkBoard::getStartFen(QGame*qgame){
  return MarkBoard::getStartFen(qgame->game);
}

int QMarkBoard::getResult(QGame*qgame){
  return MarkBoard::getResult(qgame->game);
}
int QMarkBoard::getYear(QGame*qgame){
  return MarkBoard::getYear(qgame->game);
} //{return (int)(date_GetYear(qqgame->qgame->GetDate())){}}

string QMarkBoard::getTagBuiltIn(QGame*qgame, const string& name){
  if (name=="White")
    return getPlayer(qgame,WHITE);
  else if (name=="Black")
    return getPlayer(qgame,BLACK);
  else if (name=="Event")
    return getEvent(qgame);
  else if (name=="Site")
    return getSite(qgame);
  else if (name=="Date")
    return getDate(qgame);
  else if (name=="EventDate")
    return getEventDate(qgame);
  else if (name=="ECO")
    return getECO(qgame);
  else if (name=="FEN")
    return getStartFen(qgame);
  else
    uassert(false, "QMarkBoard::getTagBuiltIn: Cannot handle built in tag of: ", name);
  return "";
}
