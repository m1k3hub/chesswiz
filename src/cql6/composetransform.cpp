#include "node.h"
bool ComposeTransform::isIdentity()const{
  for (auto t: transforms)
    if (!t->isIdentity())return false;
  return true;
}

squareT ComposeTransform::transform(squareT square)const{
  uassert(square_valid(square),"ComposeTransform::transform: bad square");
  squareT current=square;
  for(auto t: transforms){
    current=t->transform(current);
    if(!square_valid(current)) return current;
  }
  return current;
}

SquareMask ComposeTransform::transform(SquareMask mask)const{
  SquareMask m=mask;
  for(auto t:transforms) m=t->transform(m);
  return m;
}



ComposeTransform::ComposeTransform(vector<const Transform*>ts) :transforms{ts}{
  for(auto t:transforms) uassert(t,"ComposeTransform bad transform");
  uassert(transforms.size()>=2,"ComposeTransform: bad transform size");
}

ComposeTransform::ComposeTransform(const Transform*t, const Transform*s){
  uassert(t&&s,"ComposeTransform constructor bad params");
  transforms.push_back(s);
  transforms.push_back(t);
}

Direction ComposeTransform::transform(Direction d)const{
  Direction current(d);
  for(auto t:transforms) current=t->transform(current);
  return current;
}

bool ComposeTransform::flipsColor()const{
  bool flips=false;
  for(auto t:transforms) if (t->flipsColor()) flips= !flips;
  return flips;
}

vector<Transform*> ComposeTransform::composeVectors(vector<Transform*>a, vector<Transform*>b){
  vector<Transform*>ret;
  for(auto at:a)
    for (auto bt:b)
      ret.push_back(new ComposeTransform(at,bt));
  return ret;
}

vector<Transform*> ComposeTransform::composeVectors(vector<const Transform*>a, vector<const Transform*>b){
  vector<Transform*>ret;
  for(auto at:a)
    for (auto bt:b)
      ret.push_back(new ComposeTransform(at,bt));
  return ret;
}

string ComposeTransform::toString()const{
  if (isIdentity())return "";
  stringstream s;
  int ntransforms=(int)(transforms.size());
  uassert(ntransforms>0, "composetostring");
  for(int i=ntransforms-1;i>=0;i--){
    const Transform*t=transforms.at(i);
    s<<t->toString()<<' ';
  }
  string ret=s.str();
  uassert(ret.size(),"compose tostring");
  if(ret.back()==' ')ret.pop_back();
  return ret;
}

bool ComposeTransform::flipsSquareParity()const{
  bool flips=false;
  for (const Transform* t : transforms)
    if (t->flipsSquareParity())
      flips = !flips;
  return flips;
}
