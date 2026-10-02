#pragma once
#include "node.h"
/* this class is used to indicate that variations must be set in the CQL header
   the message is the message output by the error routine if it is not.
   this has no .cpp file
*/

class AssertVariationsNode : public Node{
 public:
 AssertVariationsNode(string message):theMessage{message}{}
  const string theMessage;
  string thisclass()const{return "AssertVariationsNode";}
  vnode children()const{return vnode{};}
  void deepify(){}
  void print();
  bool match_position(QPos*qpos){return true;}
  [[nodiscard]]AssertVariationsNode*clone();
  bool isGameFilter()const{return true;}
  string getMessage(){return theMessage;}
};
  
