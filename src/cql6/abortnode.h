#pragma once
#include "node.h"
/* this class generates an internal logic error on matching
*/

class AbortNode : public Node{
 public:
  AbortNode(string message);
  const string theMessage;
  string thisclass()const{return "AbortNode";}
  vnode children()const{return vnode{};}
  void deepify(){}
  void print();
  bool match_position(QPos*qpos);
[[nodiscard]]AbortNode*clone();
  string getMessage(){return theMessage;}
};
  
