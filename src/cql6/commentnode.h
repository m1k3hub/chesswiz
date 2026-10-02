#pragma once

#include "node.h"
#include "stringconverter.h"
class CommentNode : public Node{
 public:
  StringConverter* theConverter{NULL};
  bool theIsMessage{false};
  bool theIsQuiet{false};
  CommentNode(StringConverter*, bool ismessage, bool isquiet);
  string thisclass()const{return "CommentNode";}
  vnode children()const;
  void print();
  void deepify();
  bool match_position(QPos*);
[[nodiscard]]  CommentNode*clone();
};
