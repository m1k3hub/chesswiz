#pragma once
#include "node.h"
#include "positionvariable.h"

class ConsecutiveMovesNode: public Node{
 public:
  PositionVariable*left{NULL};
  PositionVariable*right{NULL};
  Range*range{NULL};
  bool quiet{false};
  ConsecutiveMovesNode(PositionVariable* l, PositionVariable* r, Range*ra, bool quiet);
  string thisclass()const override{return "ConsecutiveMovesNode";}
  void deepify()override;
[[nodiscard]]  ConsecutiveMovesNode*clone()override;
  void print()override;
  bool match_position(QPos*qpos)override;
  bool match_count(QPos*qpos,NumValue*valuep)override;
  vnode children()const override;
  void makeComments(vector<pair<QMove*,QMove*>>& pairs);
  void annotate();
  void clear();
  bool canModifyCurpos()const override{return true;}
  bool isNumeric()const override;

 private:
  vector<pair<QMove*,QMove*>> compute(QPos* leftpos, QPos*rightpos);
  vector<QMove*>movepath(QPos*start, QPos*finish);
  vector<int>movepath_to_ints(vector<QMove*>&movepath);
  vector<pair<QMove*,QMove*>> bestMovePath;
  int qmove_to_int(QMove*qmove);
  
};

    
