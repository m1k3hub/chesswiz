#include "node.h"
Node* Node::transform(Transform* t){
  uassert(t,"Ntttt");
  Node* newfilter=clone();
  newfilter->transform_in_place(t);
  return newfilter;
}


/* transform_in_place is run by a transform t AFTER the clone is run. 
   by default it invokes transform_in_place on all children (who will
   already have been cloned) then transform_members(), which just
   transforms the non-child fields of the object.
   Overridden by 
      OrbitNode::transform_in_place()
   See transform_members.cpp for the transform_members() methods
*/
void Node::transform_in_place(Transform* t){
  for (Node* child : children()){
    uassert(child,"Node::transform_in_place: unexpected null child");
    child->transform_in_place(t);
  }
  transform_members(t);
}

