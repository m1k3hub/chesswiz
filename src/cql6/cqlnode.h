#pragma once
//This file should really include node.h, but there may be some reason it doesn't
class ConsecutiveMovesNode;
class SortNode;
class PathNode;
class CqlNode : public NeverMatch{
 public:
  Node* filter{NULL};
  vector<GameFilter*> gamefilters;
  int currentGameNumber{0};
  bool searchVariations{false};
  string inputfile;
  string outputfile;
  std::set<SequenceBase*>allSequences; // all of the sequenceBase descendants;
  std::set<PathNode*>allPaths;// all of the PathNode descendants
  std::set<ConsecutiveMovesNode*>allConsecutiveMovesNodes;
  std::set<SortNode*>allSortNodes;
  void computeAllSequences();
  void computeAllPaths();
  void computeAllConsecutiveMovesNodes();
  void computeAllSortNodes();
  void completeIsBoundNodes();
  void completePathReferenceNodesInPath(PathNode*pathnode,Node*start);
  void completePathReferenceNodes();
  void completeDashOwners();
  void completeDashOwnersFromNode(Node*owner, Node*current);
  void checkAssertVariations();
  bool isSingleThread();
  bool canModifyCurpos()const override{return true;}  
  Range* nmatchesrange{NULL};
  Range* gamenumberrange{NULL};
  Range* matchCountRange{NULL};
  Environment*environment{NULL};
  vector<Variable*>getPersistentVariables()const;
  bool isQuietPersistentVariable(Variable*v)const;
  bool match_game(QGame*qame)override;
  void do_match(Node*p, QPos*qpos);
  void print()override;
  static CqlNode* create(Tokens&);
[[nodiscard]]  CqlNode* clone()override; //error if called
  string thisclass()const override{return "CqlNode";}
  vnode children()const override;
  CqlNode(vector<Node*> features,Node* node,Environment*e);
  void run();
  void deepify()override{filter=filter->clone();clonevec(gamefilters);}
  void setFirstComment(QGame*qgame);
  void annotateConsecutiveMovesNodes();
  void annotateSortNodes();
  void consecutiveMovesNodesClear();
  void sortNodesClear();
  GameSortInfo makeInfo(QGame*qgame);
  static string outputFileFromCqlFile(string cqlfile);
  void nestsClear();
  bool hasLastGameNumber();
};
