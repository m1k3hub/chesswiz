#pragma once
#include "abbreviations.h"
/*reverted from 9.250 at 9.322 to make settag non-smart*/
class QPos;
class CommentEntry{
 public:
  QPos* qpos{NULL};
  string message;
  CommentEntry(QPos*,const string&message);
  string toString();
  void print();
};
  
