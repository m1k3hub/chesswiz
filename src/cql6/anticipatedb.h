#pragma once
#include "node.h"
#include "anticipateentry.h"
#include <map>
class AnticipateDb{
 public:
  static AnticipateDb* create(string patternfile,bool isnotransform);
  static AnticipateDb* AnticipateDbP;
  string theFilename;
  bool isNoTransform{false};
  int nGames{0};
  static bool isPawnless(const QPos*qpos);
  bool find(const QPos*)const;
  const vector<AnticipateEntry>& lookup(const QPos*)const;

 private:
  static vector<Transform*> pawnlessTransforms;
  static vector<Transform*> pawnTransforms;
  static vector<Transform*> idTransforms;
  AnticipateDb(string patternfile,bool isnotransform);
  std::map<string,vector<AnticipateEntry>*>theMap;
  void initialize();
  static void initializeTransforms();
  void insertQGame(const QGame*);
  void insertQPos(const QPos*);
  void insertEntry(const AnticipateEntry&);
};
