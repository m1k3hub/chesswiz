#pragma once
#include "chesstypes.h"
class MarkBoard{
  //static methods
 public:
  static simpleMoveT* getCurrentMove(Game*game);
  static moveT* identity(Game*game);
  static bool myIsNullMove(simpleMoveT*);
  static pieceT piece_at_square(squareT square, Game*game);
  static int number_children(Game*game, bool searchvariations);
  static void move_to_child(Game*game, int child);
  static void make_move(simpleMoveT*move,Game*game); 
  static vector<simpleMoveT*> getMoves(Game*g,bool searchvariations);
  static vector<simpleMoveT*> getLegalMoves(Game*g);
  static bool inMainline(Game*game);
  static bool inVariation(Game*game);
  static bool atVarEnd(Game*game);
  static bool atVarStart(Game*game);
  static void mark(Game*game);
  static void gameForward(Game*game);
  static void gameBackup(Game*game);
  static void gameSaveState(Game*game);
  static void gameRestoreState(Game*game);
  static void gameMoveToPly(Game*game, int ply); //ply must be 0
  static void MoveIntoVariation(Game*game, int i);
  static void gameToIdentity(moveT*id, Game*game, bool variations);
  static bool gameSeekIdDescendants(moveT*id, Game*game, bool variations);
  static void gameAppendComment(Game*game, string comment);
  static void gameToChild(moveT*id, Game*game, bool vars);
  static string getEvent(Game*game);
  static resultT getResult(Game*game);
  static string getComment(Game*game);
  static vector<int> getNags(Game*game);
  static string getPlayer(Game*game,colorT color);
  static string getSite(Game*game);
  static pieceT* getBoard(Game*game);
  static colorT getToMove(Game*game);
  static int getCurrentPly(Game*game);
  static bool isInitial(Game*game);
  static bool isTerminal(Game*game);
  static simpleMoveT* getPreviousMove(Game*game);
  static bool check(Game*game);
  static bool mate(Game*game);
  static bool stalemate(Game*game);
  static int getNumber(Game*game); //not implemented, for qmarkboard
  static int getYear(Game*game);
  static string getDate(Game*game);
  static string getEventDate(Game*game);
  static int getElo(Game*game, colorT color);
  static string getECO(Game*game);
  static string getStartFen(Game*game);
  static void cleanCommentBuffer(char* buffer);
  static void setNonstandardTag(Game*game, const string& name, const string& value);
  static void gameDeleteComment(Game*game);
  };



