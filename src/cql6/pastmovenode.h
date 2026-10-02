#pragma once
#include "node.h"
enum class PastMoveType{None,Promote,Capture,NullMove,EnPassant,Primary,Secondary,OO,OOO,Castle};
class PastMoveNode : public SetBase{
 public:
  PastMoveNode(PastMoveType);
  PastMoveType theType{PastMoveType::None};
  PieceLoc* promotePieceLoc{NULL};
  Node* promoteStringFilter{NULL};
  SetBase*theCapture{NULL};
  //  static PastMoveNode*makeTo();
  //  static PastMoveNode*makeFrom();
  static PastMoveNode*makePromote(Node*);
  static PastMoveNode*makeNullMove();
  static PastMoveNode*makeEnPassant();
  static PastMoveNode*makeOO();
  static PastMoveNode*makeOOO();
  static PastMoveNode*makeCastle();
  static PastMoveNode*makePrimary();
  static PastMoveNode*makeCapture(SetBase*cap);
    static PastMoveNode*makeSecondary();
  bool isPromote()const{return theType==PastMoveType::Promote;}
  bool isNullMove()const{return theType==PastMoveType::NullMove;}
  bool isEnPassant()const{return theType==PastMoveType::EnPassant;}
  bool isPrimary()const{return theType==PastMoveType::Primary;}
  bool isSecondary()const{return theType==PastMoveType::Secondary;}
  bool isCapture()const{return theType==PastMoveType::Capture;}
  bool isCaptureNode()const override{return isCapture();} // this works for any node
  bool canModifyCurpos()const override{return isCapture();}
  bool isOO()const{return theType==PastMoveType::OO;}
  bool isOOO()const{return theType==PastMoveType::OOO;}
  bool isCastle()const{return theType==PastMoveType::Castle;}
  bool isSet()const override;
  void print()override;
  bool match_position(QPos*)override;
  SquareMask getSquares(QPos*)override;
  vnode children()const override;
  void deepify()override;
  string thisclass()const override{return "PastMoveNode";}
  string typetostring();
[[nodiscard]]  PastMoveNode*clone()override;
};  
  
   
  

