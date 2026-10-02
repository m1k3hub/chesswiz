#pragma once
#include "node.h"
class CurrentFen:public Node{
 public:
  CurrentFen(){}
  string thisclass()const{return "CurrentFen";}
  void deepify(){}
[[nodiscard]]  CurrentFen* clone();
  vnode children()const{return vnode();}
  void print();
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*,string*);
  bool isString()const{return true;}
 private:
  static string toFen(QPos*qpos);
  static string getColorString(QPos*);
  static string getCastleString(QPos*);
  static SquareMask currentForbiddenCastleMask(QPos*);
  static SquareMask forbiddenCastleMask(QPos*);
  static string epString(QPos*);
};
