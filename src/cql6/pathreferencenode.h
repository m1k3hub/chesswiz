#pragma once
#pragma once
#include "node.h"
#include "pathnode.h"
class PathReferenceNode:public Node{
 public:
  virtual bool isPathCount()const{return false;}
  virtual bool isPathMax()const{return false;}
  virtual bool isPathLastPosition()const{return false;}
  virtual bool isPathStart()const{return false;}
  virtual bool isPathDebug()const{return false;}
  PathNode*thePath{NULL};
  PathNode*getPath()const{return thePath;}
  void setPath(PathNode*s);
  bool hasPath()const{return thePath!=NULL;}
  string thisclass()const override=0;
  void print() override;
  void deepify() override;
  vnode children()const override{return vnode{};}
  bool isInternal()const; // this filter is inside the body of a path filter
  bool isExternal()const; // this filter is not insed the body of a path filter
};

