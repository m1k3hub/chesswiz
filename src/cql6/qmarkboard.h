#pragma once
#include "util.h"
#include "markt.h"
class QGame;
class QMove;
class QPos;
class QMarkBoard{
 public:
  static QPos* identity(QGame*qgame);
  static pieceT piece_at_square(squareT square, QGame*game);
  static int number_children(QGame*qgame);
  static void move_to_child(QGame*qgame, int child);
  static vector<QMove*>* getMoves(QGame*qgame);
  static bool inMainline(QGame*qgame);
  static bool inVariation(QGame*qgame);
  static bool atVarEnd(QGame*qgame);
  static bool atVarStart(QGame*qgame);
  static void gameBackup(QGame*qgame);
  static void gameMoveToPly(QGame*qgame, int ply); //ply must be 0
  static void gameToIdentity(QPos*id, QGame*qgame);
  static void gameAppendComment(QGame*qgame, string comment);
  static void gameAppendComment(QGame*qgame, QPos*loc, string comment);
  static void gameToChild(QPos*id, QGame*qgame);
  static string getEvent(QGame*qgame);
  static string getDate(QGame*qgame);
  static string getEventDate(QGame*qgame);
  static string getStartFen(QGame*qgame);
  static string getOriginalComment(QGame*qgame);
  static string getPlayer(QGame*qgame,colorT color);
  static int getElo(QGame*qgame,colorT color);
  static string getSite(QGame*qgame);
  static pieceT* getBoard(QGame*qgame);
  static colorT getToMove(QGame*qgame);
  static int getCurrentPly(QGame*qgame);
  static bool isInitial(QGame*qgame);
  static bool isTerminal(QGame*qgame);
  static QMove* getPreviousMove(QGame*qgame);
  static bool check(QGame*qgame);
  static bool mate(QGame*qgame);
  static bool stalemate(QGame*qgame);
  static int getNumber(QGame*qgame); //not implemented, for qmarkboard
  static int getVarLevel(QGame*qgame);
  static int getResult(QGame*qgame);
  static int getMark(QGame*qgame,squareT square);
  static squareT getSquare(QGame*qgame,markT mark);
  static int getYear(QGame*qgame); //{return (int)(date_GetYear(qgame->game->GetDate()));}
  static string getTagBuiltIn(QGame*qgame, const string& name);
  static string getECO(QGame*qgame);
};


