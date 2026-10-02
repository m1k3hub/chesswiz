#pragma once
#include "node.h"
#include "commentnode.h"

class MoveBase:public SetBase{
 public:
  SetBase* from{NULL};
  SetBase* to{NULL};
  PieceLoc* promote{NULL};
  SetBase* enpassantsquare{NULL};
  SetBase* capture{NULL};
  CommentNode* commentNode{NULL};
  bool nullMove{false};
  bool primaryMove{false};
  bool secondaryMove{false};
  bool returnFrom{false};
  bool returnTo{false};
  bool returnCapture{false};
  SquareMask fromMask;
  SquareMask toMask;
  SquareMask enpassantMask;
  SquareMask captureMask;
  MoveBase(SetBase*from, SetBase* to, PieceLoc* promote,SetBase* enpassant,SetBase*capture,CommentNode*comment,bool nullmove,bool mainline, bool variation,bool returnfrom, bool returnto,bool returncapture);
  void setMasks(QPos*);
  void print();
  vnode children()const;
  bool match_position(QPos*);
  virtual SquareMask getSquares(QPos*)=0;
  bool match_move(QMove*move);
  void deepify();
  squareT returnSquare(const QMove*qmove)const;
};
  
class MovePastNode:public MoveBase{
 public:
  string thisclass()const{return "MovePastNode";}
[[nodiscard]]  MovePastNode*clone();
  SquareMask getSquares(QPos*);
  MovePastNode(SetBase*from, SetBase* to, PieceLoc* promote,SetBase* enpassant,SetBase*capture,CommentNode*comment,bool nullmove,bool mainline, bool variation,bool returnfrom, bool returnto,bool returncapture);
};

class MoveFutureNode:public MoveBase{
 public:
  string thisclass()const{return "MoveFutureNode";}
[[nodiscard]]  MoveFutureNode*clone();
  MoveFutureNode(SetBase*from, SetBase* to, PieceLoc* promote,SetBase* enpassant,SetBase*capture,CommentNode*comment,bool nullmove,bool mainline, bool variation,bool returnfrom, bool returnto,bool returncapture);
  QMove* requiredMove=NULL; // used by Future Node
  SquareMask getSquares(QPos*);
};

