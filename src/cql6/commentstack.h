#pragma once
#include "commententry.h"
class CommentStack{
 public:
  CommentStack();
  vector<CommentEntry>stack;
  int size();
  bool empty();
  bool nonempty();
  void push(CommentEntry &entry);
  void pop();
  string toString();
  void print();
  CommentEntry &at(int);
  void transfer(int start, CommentStack*dest);
  void clear();
  int markComments();
  void restoreComments(int top);
  void deleteComments(int start, int stop);
  void reverse();
};
