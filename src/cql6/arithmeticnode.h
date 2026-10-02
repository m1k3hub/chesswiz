#include "node.h"
#include "variable.h"

class ArithmeticNode : public Node{
 public:
  char namec{'Z'};
  Node* left{NULL};
  Node* right{NULL};
  ArithmeticNode(char namec, Node* l, Node* r);
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  bool isNumeric()const{return true;}
  void print();
  string thisclass()const{return "ArithmeticNode";}
  [[nodiscard]]ArithmeticNode*clone();
  NumValue operate(NumValue l, NumValue r);
  vnode children()const;
  void deepify(){left=left->clone();right=right->clone();}
  string getOps(){return Ops;}
  static const string Ops; //"+-*/%"
  static bool isOp(char c);
  static bool isOp(const string& name);
};
