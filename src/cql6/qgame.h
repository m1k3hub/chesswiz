#pragma once
#include "qpos.h"
#include "pathstatus.h"
#include "pgnsource.h"
#include "commentstack.h"
#include "tagsection.h"
#include "regexhistory.h"
#include <regex>
class PathNode; // used for PathLastMatched;
class QGame{
 public:
  QPos* getNewQPos();
  QGame(PgnSource*source,bool searchvariations);
#ifdef CQL6_EMBEDDED // scidb: structured game feed
  QGame(class ScidbGameSource* scidb_source, int thread_idx, bool searchvariations);
  class ScidbGameSource* scidbSource{NULL};
  int threadIndex{0};
  bool scidbParseNextGame();
  unsigned stateFeatures{7}; // scidb: check=1, mate=2, stalemate=4; conservative default
  long nSkippedGames{0}; // scidb: games rejected by the feed (counted, search continues)
  long nTruncatedGames{0};
#endif
  //  QGame(Game*game,bool variations);
  //  ~QGame();
  Game*game{NULL};
  /*PgnSource stuff*/
  bool pgnUseSource{false};
  PgnSource* pgnSource{NULL};
#ifndef CQL6_EMBEDDED
  static const int pgnBufferCapacity{1000000};
  char pgnBuffer[pgnBufferCapacity];
#else
  static const int pgnBufferCapacity{1};
  char pgnBuffer[1];
#endif
  int pgnGamesRead{0};
  TagSection* getTagSection();
  const TagSection* getTagSection()const;

  QPos*root{NULL};
  vector<QPos*>allQPos; // in topologically sorted order
  PgnParser* thePgnParser{NULL};
  QPos*getQPos(int index)const;
  bool parseNextGame();
  bool searchVariations{false};
  MFile * theMFile;
  void print();
  void verifyRoot();
  int theGameNumber{0};
  bool foundCook{false}; // whether this game has a substring "<cook"
  bool foundCookValid{false}; //whether foundCook has been computed
  QPos*getRoot(){return root;}
  void prepareComments();
  void mergeComments(bool prepared=false);
  int getGameNumber()const{return theGameNumber;}
  int nQPos();
  bool pgnParseNextGame();
  CommentStack* getCommentStack(){return &theComments;}
  void pushComment(QPos*,const string&);
  int markComments();
  void restoreComments(int); // exclusive
  void deleteComments(int start, int stop);
  void doSetTag(const string&name, const string& value);
  void registerRegexMatch(const std::smatch&);
  void clearRegexHistory();
  RegexHistory* getRegexHistory(){return &theRegexHistory;}
  const RegexHistory* getRegexHistory()const{return &theRegexHistory;}
 private:
  //QPos pool
  static const int QPosPoolSize{50000};
#ifndef CQL6_EMBEDDED
  std::array<QPos,QPosPoolSize> QPosPool;
#else
  // scidb: (Task 3 §E4) chunked pool: the standalone program embeds 50000 QPos
  // (~36 MB) per QGame; with 47 threads that is ~1.7 GB up front. Embedded, we
  // allocate chunks of 512 QPos on demand (chunk storage never moves, so issued
  // QPos* stay valid) and a game only costs what it actually uses.
  static const int QPosChunkSize{512};
  std::vector<std::unique_ptr<std::array<QPos,QPosChunkSize>>> QPosChunks;
#endif
  int nextQPosIndex{0};
  CommentStack theComments;
  TagSection theTagSection;
  RegexHistory theRegexHistory;
public:
  //Path stuff
  PathStatus thePathStatus;
  PathStatus getPathStatus()const{return thePathStatus;}
  void setPathStatus(PathStatus s){thePathStatus=s;}
  QGame*clone()const; // for anticipate
  
};
