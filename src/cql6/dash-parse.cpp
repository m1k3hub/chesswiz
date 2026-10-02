#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "nodeheaders.h"

SetBase*Tokens::match_dash_right(){
  Node*ret=NULL;
  int x=save();
  if(peek_equals_sign())
    return NULL;
  if(peek_lparen())
    return NULL;
  Variable*v=match_variable_use();
  if(v&&peek_equals_sign()){
    if(!v->isSet())
      show_error("non-set variable immediately follows --"s+v->name);
    return v->asSet();
  }
  restore(x);
  ret=match_dash_tie_x();
  if(!ret)return NULL;
  if(!ret->isSet())
    show_error("expected a set filter on the right side of --");
  return ret->asSet();
}

bool Tokens::peek_equals_sign(){
  SpecialToken*token=dynamic_cast<SpecialToken*>(current());
  return token&&token->eq("=");
}

bool Tokens::peek_lparen(){
  SpecialToken*token=dynamic_cast<SpecialToken*>(current());
  return token&&token->eq("(");
}


Node*Tokens::match_dashnode_from_prefix(SetBase*left,DashToken*dashtoken){
  bool lefttie{dashtoken->isLeftTie()};
  bool righttie{dashtoken->isRightTie()};
  Node*promotionnode=NULL;
  SetBase* right{NULL};
  if(lefttie&&left==NULL){
      stringstream s;
      s<<"in attempting to parse '--', there was a character immediately to the left where CQL is expecting a set filter. Try adding a space between the character immediately to the left of the '--' and the '--' itself. Outputting a representation of the dash token here: ";
      cout<<dashtoken->toString()<<endl;
      show_error(s.str());
  }
  if (righttie){
    right=match_dash_right();
    promotionnode=match_dash_promotion();
  }
  bool iscount{false};
  CaptureType cap=dashtoken->getCaptureType();
  uassert(captureTypeValid(cap),"unknown capture type in dash-parse");
  Node*target=match_dash_target();
  if(match_lparen())
    show_error("There is a '(' character immediately following a -- filter. This might not be an error, but it might indicate that it begins a target specification for the -- filter, and whitespace was inadvertently included between the end of the -- filter and the beginning of the intended target filter.");
  if(promotionnode && !target)
    target=new AndNode(promotionnode, new TrueNode());
  else if (promotionnode && target)
    target=new CompoundNode(vector<Node*>{promotionnode,target});
  return new DashNode(left,right,target,cap,iscount);
  }
       
Node* Tokens::match_dash_promotion(){
  if(!match_special("=")) return NULL;
  Node*node=match_node();
  PieceLoc*p=dynamic_cast<PieceLoc*>(node);
  if(p){
    if(!p->isPurePiece())
    show_error("The promoted piece type, if it is a piece designator, must be a piece name or a set of piecenames, e.g. '(R)' or '([RB])'");
    return PastMoveNode::makePromote(p);
  }
  if(dynamic_cast<AnyNode*>(node)) node=new StringLiteralNode("");
  if(!node->isString())
    show_error("expected either a piece designator or a string filter as a promotion type specifier");
  return PastMoveNode::makePromote(node);
}
  
Node* Tokens::match_dash_target(){
  SpecialToken*lparen=dynamic_cast<SpecialToken*>(current());
  if(!lparen||!lparen->eq("("))return NULL;
  if(lparen->followsWhitespace())
    show_error("There  must be no whitespace between the '--' filter and the '(' which begins the target specification");
  forward();
  vector<Node*>v;
  while(true){
    if(match_rparen())
      break;
    Node*node=match_node();
    if(!node)
      show_error("while parsing apparent target after '-- (' unable to get a node. Expected a sequence of nodes, e.g. '-- (mate from)'");
    v.push_back(node);
  }
  if(v.empty())
    show_error("while empty sequence of targets following '--': got '()' instead of a nonempty list of targets");
  if(v.size()==1)
    return v[0];
  return new CompoundNode(v);
}
