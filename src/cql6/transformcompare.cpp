#include "orbitnode.h"
#include "node.h"
#include "nodeheaders.h"

bool Direction::operator<(const Direction&other)const{
  if(xoffset<other.xoffset)return true;
  if(xoffset>other.xoffset)return false;
  return yoffset<other.yoffset;
}

bool DirectionParameter::operator<(const DirectionParameter&other)const{
  uassert(range==other.range,"directionparameter operator< range");
  uassert(directions.size()==other.directions.size(),"directionparameter directions < size");
  return directions<other.directions;
}

bool OrbitElement::operator<(const OrbitElement &other)const{
  return node->transformless(other.node);
}

bool Node::transformless(const Node*r)const{
  if(this==r)return false;
  if(0){
    cout<<"transformless: called with this of: \n";
    ((Node*)this)->print();
    cout<<"transformless: called with other of: \n";
    ((Node*)r)->print();
  }
        
  if(transformmemberless(r)) {if(0)cout<<"transformless 1: returning true\n";return true;}
  if(r->transformmemberless(this)){if(0)cout<<"transformless 2: returning false\n";return false;}
  vnode mychildren=children();
  vnode theirchildren=r->children();
  int len=(int)(mychildren.size());
  uassert(len==theirchildren.size(),"transformcompare: child size mismatch");
  uassert(thisclass()==r->thisclass(),"transformcompare: class mismatch");
  for (int i=0;i<len;++i){
    auto mychild=mychildren[i];
    auto otherchild=theirchildren[i];
    if(mychild->transformless(otherchild)){if(0)cout<<"transformless 3: T\n";return true;}
    if(otherchild->transformless(mychild)){if(0)cout<<"transformless 4: F\n";return false;}
  }
  {if(0)cout<<"transformless 5: F\n";return false;}
}

/* transformemberless section. It is very important that all classes
   with specialized transform_members() have an entry here!!*/

bool Node::transformmemberless(const Node*r)const{
  return false;
}

bool ResultNode::transformmemberless(const Node*r)const{
  const ResultNode* other=dynamic_cast<const ResultNode*>(r);
  uassert(other,"ResultNode tml arg");
  return result<other->result;
}

bool PieceLoc::transformmemberless(const Node*r)const{
  const PieceLoc*other=dynamic_cast<const PieceLoc*>(r);
  uassert(other!=NULL,"PieceLoc::tmci: other");
  auto mymask=squaremask.mask;
  auto omask=other->squaremask.mask;
  if(mymask<omask)return true;
  if(omask<mymask)return false;
  if(colorFlags<other->colorFlags)return true;
  if(colorFlags>other->colorFlags)return false;
  if(thePieces<other->thePieces)return true;
  if(thePieces>other->thePieces)return false;
  return false;
}

bool ToMoveNode::transformmemberless(const Node*r)const{
  const ToMoveNode*other=dynamic_cast<const ToMoveNode*>(r);
  uassert(other!=NULL,"tomovenode tcompared bad arg");
  return color<other->color;
}

bool ColorValueNode::transformmemberless(const Node*r)const{
  const ColorValueNode*other=dynamic_cast<const ColorValueNode*>(r);
  uassert(other!=NULL,"colorvaluenode tcompare arg");
  return color<other->color;
}

bool EloNode::transformmemberless(const Node*r)const{
  const EloNode*other=dynamic_cast<const EloNode*>(r);
  uassert(other!=NULL,"elonode tcompare arg");
  uassert(range==other->range,"elo tmemberless range");
  return color <other->color;
}

bool RayNode::transformmemberless(const Node*r)const{
  const RayNode*other=dynamic_cast<const RayNode*>(r);
  uassert(other!=NULL,"raynode tcompare arg");
  return directions<other->directions;
}

bool VectorNode::transformmemberless(const Node*r)const{
  const VectorNode*other=dynamic_cast<const VectorNode*>(r);
  uassert(other,"vectornode tcompare arg");
  return parameter.directions<other->parameter.directions;
}

bool OrbitNode::transformless(const Node*r)const{
  const OrbitNode*other=dynamic_cast<const OrbitNode*>(r);
  uassert(other,"orbitnode tcompare arg");
  uassert(isOrbitComputed()&&other->isOrbitComputed(),"orbitnode tcompare expansion)");
  uassert (range==other->range,"ranges differ in orbitnode comparison");
  return theOrbit < other->theOrbit;
}

bool NoTransformNode::transformmemberless(const Node*r)const{
  return false;
}

bool SquareParityNode::transformmemberless(const Node*r)const{
  const SquareParityNode*other=dynamic_cast<const SquareParityNode*>(r);
  uassert(other!=NULL, "squareparitynode:tcompare arg");
  return isLight()<other->isLight();
}

  

bool TagBuiltInNode::transformmemberless(const Node*r)const{
  const TagBuiltInNode*other=dynamic_cast<const TagBuiltInNode*>(r);
  uassert(other!=NULL,"tbin transformmembersless");
  uassert (theName==other->theName || theName=="White"&&other->theName=="Black"||
	   theName=="Black"&&other->theName=="White","tbin tml comparison");
  return theName < other->theName;
}
