#pragma once
#include "node.h"
#include "anticipatedb.h"
#include "numericvariable.h"
class AnticipateNode:public Node{
 public:
  AnticipateDb* theDb{NULL};
  AnticipateNode(string patternfile,NumericVariable*minremoteqgamevar,bool isnotransform);
  string patternFile;
  NumericVariable*minRemoteQGameVar{NULL};
  bool isNoTransform{false};
  //  NumericVariable*nMatchesVar{NULL};
  bool match_position(QPos*)override;
  void print()override;
  string thisclass()const override{return "AnticipateNode";}
  [[nodiscard]]AnticipateNode*clone()override;
  void deepify() override;
  vnode children()const override{return vnode{};}
private:
  void updateMinRemoteQGame(int qgame);
};
  

  
  
  
  
  
