#include "node.h"
bool ColorTransform::isIdentity()const{return false;}
Transform* ColorTransform::flipColorTransform(){
  Transform*ct=new ColorTransform();
  Transform*fh=DihedralTransform::flipHorizontal();
  return ct->compose(fh);
}

string ColorTransform::toString()const{
  return "invertcolor";
}

