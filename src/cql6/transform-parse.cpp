#include "node.h"
#include "tokens.h"
OrbitNode* Tokens::match_swapcolortransform(){
  if(!match_keyword("reversecolor"))
    return NULL;
  Node*node=match_node();
  if(!node)
    show_error("After a 'reversecolor' keyword expecting a filter");
  vector<Transform*>transforms;
  transforms.push_back(ColorTransform::flipColorTransform());
  return OrbitNode::create(transforms,node,NULL);
}
  
OrbitNode* Tokens::match_shifttransform(){
  KeywordToken *k=match_keyword("shift");
  if(!k)k=match_keyword("shiftvertical");
  if(!k)k=match_keyword("shifthorizontal");
  if(!k) return NULL;
  Range*range=match_range();
  Node*node=match_node();
  if(!node)
    show_error("After a shift keyword expecting a filter specification");
  vector<Transform*>transforms;
  transforms.push_back(new IdentityTransform());
  if(k->eq("shift"))
    for(auto t:ShiftTransform::allShift())
      transforms.push_back(t);
  else if (k->eq("shifthorizontal"))
    for(auto t:ShiftTransform::shiftHorizontal())
      transforms.push_back(t);
  else if (k->eq("shiftvertical"))
    for(auto t:ShiftTransform::shiftVertical())
      transforms.push_back(t);
  else uassert(false, "internal shift");
  return OrbitNode::create(transforms,node,range);
}
  
    
OrbitNode* Tokens::match_fliptransform(){
  KeywordToken *k=NULL;
  if(!k) k=match_keyword("flip");
  if(!k) k=match_keyword("flipvertical");
  if(!k) k=match_keyword("fliphorizontal");
  if(!k) k=match_keyword("flipcolor");
  if(!k) k=match_keyword("rotate90");
  if(!k) k=match_keyword("rotate45");
  if(!k) k= match_keyword("flipdihedral");
  if(!k) k=match_keyword("dihedral");
  if(!k) return NULL;
  Range*range=match_range();
  Node*node=match_node();
  if(!node)
    show_error("After a flip keyword, expecting a filter specification");
  vector<Transform*> transforms;
  transforms.push_back(new IdentityTransform());
  if(k->eq("flip")||k->eq("flipdihedral")||k->eq("dihedral"))
    for(auto t: DihedralTransform::allDihedral())
      transforms.push_back(t);
  else if (k->eq("rotate90"))
    for(auto t:DihedralTransform::rotations())
      transforms.push_back(t);
  else if (k->eq("rotate45"))
    for(auto t:PiOver4Transform::rotations())
      transforms.push_back(t);
  else if(k->eq("flipvertical"))
    transforms.push_back(DihedralTransform::flipVertical());
  else if(k->eq("fliphorizontal"))
    transforms.push_back(DihedralTransform::flipHorizontal());
  else if(k->eq("flipcolor"))
    transforms.push_back(ColorTransform::flipColorTransform());
  else
    uassert(false,"internal fliptransform");
  return OrbitNode::create(transforms,node,range);
}

vector<Transform*>Tokens::match_qtransforms(){
  if(match_keyword("shift"))
    return ShiftTransform::allShift();
  else if (match_keyword("shifthorizontal"))
    return ShiftTransform::shiftHorizontal();
  else if (match_keyword("shiftvertical"))
    return ShiftTransform::shiftVertical();
  else if (match_keyword("flip"))
    return DihedralTransform::allDihedral();
  else if (match_keyword("rotate90"))
    return DihedralTransform::rotations();
  else if (match_keyword("rotate45"))
    return PiOver4Transform::rotations();
  else if (match_keyword("flipvertical"))
    return vector<Transform*>{DihedralTransform::flipVertical()};
  else if (match_keyword("fliphorizontal"))
    return vector<Transform*>{DihedralTransform::flipHorizontal()};
  else if (match_keyword("flipcolor"))
    return vector<Transform*>{ColorTransform::flipColorTransform()};
  return vector<Transform*>{};
}

Node* Tokens::orbitnode_from_keyword(const string& name, Node*node){
  uassert(node,"orbitnode_from_keyword: node");
  vector<Transform*>transforms=transforms_from_keyword(name);
  if(transforms.empty())return NULL;
  return OrbitNode::create(transforms,node,NULL);
}

