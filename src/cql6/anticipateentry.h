#pragma once
#include "node.h"
#include "qpos.h"
#include <array>
#include "transform.h"
class AnticipateEntry{
 public:
  const string key;
  const int gameNumber;
  const int moveNumber;
  const colorT sideToMove;
  const Transform* theTransform;
  string toString()const;
  static string computeKey(const std::array<pieceT,64>&boardref, colorT sidetomove);
  static string computeKey(const pieceT*,colorT sidetomove);
  static string computeKey(const QPos*);
  static std::array<pieceT,64>convertBoard(const pieceT*board);
  AnticipateEntry(const string&key,
		  int gamenumber,
		  int movenumber,
		  colorT sidetomove,
		  Transform*transform);
  static bool transformable(const std::array<pieceT,64>&, Transform*);
  static std::array<pieceT,64> transform(const std::array<pieceT,64>&,Transform*);
  bool operator==(const AnticipateEntry& o)const;
  static vector<AnticipateEntry> entriesFromQPos(const QPos*,
						 const vector<Transform*>);
};
  
