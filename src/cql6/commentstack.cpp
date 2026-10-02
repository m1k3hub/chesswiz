#include "commentstack.h"
#include "cqlassert.h"
#include <iterator>
#include <algorithm> // Apparently necessary for Linux compile see 9.180 notes
CommentStack::CommentStack(){
  stack.reserve(1024);
}
int CommentStack::size(){
  return (int)(stack.size());
}
bool CommentStack::empty(){
  return stack.empty();
}
bool CommentStack::nonempty(){
  return !empty();
}

void CommentStack::pop(){
  stack.pop_back();
}

string CommentStack::toString(){
  stringstream s;
  s<<"CommentStack: size: %d\n",size();
  for(int i=0;i<size();++i)
    s<<"  CommentStackEntry "<<i<<" of "<<size()<<": "<<stack.at(i).toString()<<'\n';
  return s.str();
}

CommentEntry& CommentStack::at(int i){
  uassert(i>=0&&i<stack.size(),"CommentStack:at: bad i");
  return stack[i];
}

void CommentStack::transfer(int start,CommentStack*dest){
  int oldsize=size();
  int olddestsize=dest->size();
  uassert(start>=0&&start<=size()&&dest&&dest!=this,"CommentStack transfer args");
  int ntransfers=size()-start;
  std::move(stack.begin()+start,stack.end(),std::back_inserter(dest->stack));
  stack.erase(stack.begin()+start,stack.end());
  if(!(size()==oldsize-ntransfers&& dest->size()==olddestsize+ntransfers)){
    printf("transfer failure: start: %d oldsize: %d currsize: %d olddestsize: %d currdestsize: %d ntransfers: %d\n",
	   start,oldsize,size(),olddestsize,dest->size(),ntransfers);
    uassert(false,"cs bad transfer");
  }
}

void CommentStack::clear(){
  stack.clear();
}
    
void CommentStack::push(CommentEntry& entry){
  stack.push_back(std::move(entry));
}

int CommentStack::markComments(){
  return size();
}

void CommentStack::restoreComments(int desttop){
  if(desttop==size())return;
  stack.erase(stack.begin()+desttop,stack.end());
  uassert(size()==desttop,"qgame popcomments internal");
}

//I haven't checked that this definitely works if stop is
// the end but I assume it does
void CommentStack::deleteComments(int start,int stop){
  uassert(start<=stop && start>=0&&stop<=size(),"csdc args");
  if(start==stop)return;
  int oldsize=size();
  stack.erase(stack.begin()+start,stack.begin()+stop);
  uassert(size()==oldsize-(stop-start),"csdc size");
}

void CommentStack::reverse(){
  std::reverse(stack.begin(),stack.end());
}
