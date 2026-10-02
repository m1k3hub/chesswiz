#include "orbitnode.h"
// for OrbitNode::transform_in_place(Transform*t) see the file computeorbit.cpp

OrbitNode* OrbitNode::create(vector<Transform*> ts,Node*n,Range*r){
  uassert(n, "OrbitNode::create: null node");
  OrbitNode* nbasenode=dynamic_cast<OrbitNode*>(n);
  Range*subrange=NULL;
  if(nbasenode)subrange=nbasenode->range;
  if(!r&&nbasenode){
    uassert(!nbasenode->isOrbitComputed(),"OrbitNode::create: nbasenode expanded, internal logic error");
    vector<Transform*>basets=nbasenode->getTransforms();
    vector<Transform*>composedts=
      ComposeTransform::composeVectors(ts,basets);
    Node* source=nbasenode->getSource();
    return create(composedts,source,subrange);
  }
  return new OrbitNode(ts,n,r);
}

bool OrbitNode::isSet()const{
  if (range)return false;
  if(!isOrbitComputed())return filter->isSet();
  uassert(originalFilter,"OrbitNode::isSet: no originalFilter");
  return originalFilter->isSet();
}

bool OrbitNode::isNumeric()const{
  if(range)return true;
  if(!isOrbitComputed())return filter->isNumeric();
  uassert(originalFilter,"OrbitNode::IsNumeric: no originalFilter");
  return originalFilter->isNumeric();
}


SquareMask OrbitNode::getSquares(QPos*qpos){
  uassert(isSet(),"Attempt to use a transform node as a square set when its argument is not a set");
  uassert(isOrbitComputed(),"tsn not expanded");
  SquareMask mask;
  for(auto & e : theOrbit){
    SetBase* converted=dynamic_cast<SetBase*>(e.node);
    uassert(converted,"Internal error in orbitnode.getSquares: a transformed filter is not a setbase");
    uassert(converted->isSet(),"internal error in TransforNode::getSquares: converted transformed filter is not a set");
    mask|=converted->getSquares(qpos);
  }
  return mask;
}

int OrbitNode::orbitLength()const{
  uassert(isOrbitComputed(),"orbitlength not defined here");
  return (int)(theOrbit.size());
}

vnode OrbitNode::children()const{
  vnode v;
  if(isOrbitComputed())
    for (auto&e:theOrbit)
      v.push_back(e.node);
  else{
    uassert(filter,"orbitnode children err");
    v.push_back(filter);
    }
  return v;
}
  
OrbitNode::OrbitNode(vector<Transform*>ts,Node*f,Range*r):
  transforms(ts),filter(f),range(r){
  uassert(filter,"tntn f");
  for(auto t:transforms) uassert(t,"tntn t");
  uassert(ts.size(),"OrbitNode: got null transform set");
  range=r;
}

/*return the number of matching transforms*/
int OrbitNode::compute_match_count(QPos*qpos){
  uassert(isOrbitComputed(),"orbitnode mp not expanded");
  int ret=0;
  for(auto &e:theOrbit)
    if(e.node->match_position(qpos))++ret;
  return ret;
}
  
bool OrbitNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  int matchcount=compute_match_count(qpos);
  bool ret=false;
  if(range) ret=range->valid(matchcount);
  else ret= (matchcount>0);
  if(!ret)
    qpos->restoreComments(mark);
  return ret;
}

//compute the numeric value when there is a range and we want the number of matching
// transforms
bool OrbitNode::match_range(QPos*qpos,NumValue*value){
  uassert(range&&isOrbitComputed(),"OrbitNode::match_range: internal args");
  int mark=qpos->markComments();
  int matchcount=compute_match_count(qpos);
  bool ret=range->valid(matchcount);
  if(ret) *value=matchcount;
  else qpos->restoreComments(mark);
  return ret;
}
  
bool OrbitNode::match_count(QPos*qpos,NumValue*value){
  uassert(isNumeric()&&isOrbitComputed(),"Attempt to sort or count a transform that is not numeric and lacks the 'count' keyword");
  if (range) return match_range(qpos,value);
  return match_count_max(qpos,value);
}

/*compute the numeric value as the max of all the included values*/
bool OrbitNode::match_count_max(QPos*qpos,NumValue*value){
  uassert(!range
	  &&isNumeric()
	  &&isOrbitComputed(),"OrbitNode: cannot get max of non-numeric filter or range exists");
  int originalmark=qpos->markComments(); //mark at the beginning of call
  bool seenMax{false}; //have we matched a numeric filter?
  NumValue bestMax{-100000}; //best max so far
  for(auto&e:theOrbit){
    int currentmark=qpos->markComments(); //mark at start of current orbit element
    if (!e.node->match_count(qpos,value)) continue;
    if(!seenMax){
      bestMax=*value;
      seenMax=true;}
    else if (*value > bestMax){
      qpos->deleteComments(originalmark,currentmark);
      bestMax= *value;
    }
    else if (*value == bestMax){
      continue;
    }
    else if(*value < bestMax)
      qpos->restoreComments(currentmark);
    else
      uassert(false,"OrbitNode mcm internal");
  }
  if(!seenMax) return false;
  *value=bestMax;
  return true;
}
    
      

