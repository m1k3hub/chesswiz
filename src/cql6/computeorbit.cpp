#include "orbitnode.h"
#include "pieceloc.h"
void OrbitNode::deepify(){
  uassert(!isOrbitComputed(),"OrbitNode: deepify: internal");
  filter=filter->clone();
}

OrbitNode* OrbitNode::clone(){
  uassert(!isOrbitComputed(),"cannot clone expanded orbitnode");
  OrbitNode*ret=new OrbitNode(*this);
  ret->deepify();
  cloneverify(this,ret);
  return ret;
}

void OrbitNode::computeOrbit(){
  uassert(!isOrbitComputed()&&filter!=NULL&&originalFilter==NULL,"computeorbits args");
  //computeOrbits must not yet have been called on filter
  std::set<OrbitElement>orbitset;
  for(auto transform : transforms){
    Node* transformednode=filter->transform(transform);
    uassert(transformednode,"null transform or wrong type in expand()");
    uassert(transformednode->thisclass()==filter->thisclass(),"computeorbits class mismatch");
    transformednode->computeOrbit();
    if(transformednode->hasEmptySquareMask())
      continue;
    orbitset.insert(OrbitElement(transform,transformednode));
  }
  for(OrbitElement o:orbitset)
    theOrbit.push_back(o);
  theOrbitComputed=true;
  originalFilter=filter;
  filter=NULL;
}

void Node::computeOrbit(){
  for(Node* child:children()){
    uassert(child,"null child expand");
    child->computeOrbit();
  }
}

/*hasEmptySquareMask() is true of a node if:
       1. it is a PieceLoc with an empty square mask
       2. It is an orbit node with a computed empty orbit.
       3. If it has a child with an empty square mask
*/
bool Node::hasEmptySquareMask()const{
  for(auto child:children())
    if(child->hasEmptySquareMask())
      return true;
  return false;
}
bool OrbitNode::hasEmptySquareMask()const{
  uassert(isOrbitComputed(),"OrbitNode: hasEmptySquareMask on uncomputed orbit");
  return orbitLength()==0;
}

bool PieceLoc::hasEmptySquareMask()const{
  return squaremask.empty();
}

/*transform_in_place is run AFTER a node is cloned clone() by
  Node::transform(Transform*)

It must not be run on a computed orbit
*/

void OrbitNode::transform_in_place(Transform*t){
  uassert(!isOrbitComputed(),"transform_in_place on orbit computed node");
  uassert(filter,"orbitnode transform_in_place");
  for (int i = 0; i< (int)(transforms.size());++i)
    transforms[i]=new ComposeTransform(t,transforms[i]);
}
