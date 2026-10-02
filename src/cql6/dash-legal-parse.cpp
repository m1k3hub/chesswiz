#include "node.h"
#include "tokens.h"
#include "dashnode.h"

MoveLegalNode* Tokens::match_legal_dash(){
  bool ispseudolegal{false};
  if(match_keyword("legal"))
     ispseudolegal=false;
  else if(match_keyword("pseudolegal"))
    ispseudolegal=true;
  else return NULL;
  Node*node=match_mulop_x();
  if(!node)
    show_error("could not read -- filter following 'legal' or 'pseudolegal'");
  DashNode*dashnode=dynamic_cast<DashNode*>(node);
  if(!dashnode){
    cout<<"Invalid node type following 'legal': expected a dash node but got:\n";
    node->print();
    show_error("following 'legal' or 'pseudolegal', expected a -- filter, but got another unexpected type of filter");
  }
  if(!captureTypeIsNonCapture(dashnode->getCaptureType()))
    show_error("'legal' and 'pseudolegal' are not supported with capturing dashnodes '[x]'. Use normal -- instead if possible.");
  SetBase*left=dashnode->getLeft();
  SetBase*right=dashnode->getRight();
  Node*target=dashnode->getTarget();
  PastMoveNode*pastmovenode=dynamic_cast<PastMoveNode*>(target);
  if(target&&!pastmovenode){
    cout<<"illegal target in dash following 'legal --': \n";
    node->print();
    show_error("The target, if any, following 'legal --' must be one of o-o, o-o-o, castle, or enpassant. Either promotion was specified in the -- filter, or an unsupported target filter type was used with 'legal/pseudolegal'");
  }
  string castlefromstr="Ke1|ke8";
  string ootostr="[g1,g8]";
  string oootostr="[c1,c8]";
  string castletostr="[g1,g8,c1,c8]";
  SetBase*castlefrom{NULL};
  SetBase*castleto{NULL};
  SetBase*ep{NULL}; // the target enpassant capture squares. Will be AnyNode if true, else NULL
  if(pastmovenode&&pastmovenode->isOO()){
    castlefrom=new NoTransformNode(set_from_string(castlefromstr));
    castleto=new NoTransformNode(set_from_string(ootostr));
  }
  else if (pastmovenode&&pastmovenode->isOOO()){
    castlefrom=new NoTransformNode(set_from_string(castlefromstr));
    castleto=new NoTransformNode(set_from_string(oootostr));
  }
  else if (pastmovenode&&pastmovenode->isCastle()){
    castlefrom=new NoTransformNode(set_from_string(castlefromstr));
    castleto=new NoTransformNode(set_from_string(castletostr));
  }
  else if (pastmovenode&&pastmovenode->isEnPassant()){
    ep=new AnyNode();
  }
  else if (pastmovenode)
    show_error("Invalid target type for 'legal' or 'pseudolegal'. The only allowed targets after 'legal --- (target)' are at most one of 'o-o', 'o-o-o', 'castle', and 'enpassant'");
  left=OnNode::makeVirtualOnNode(left,castlefrom);
  right=OnNode::makeVirtualOnNode(right,castleto);
  if(!left) left=new AnyNode();
  if(!right) right=new AnyNode();
  return new MoveLegalNode(left, right, ep, NULL, ispseudolegal, false, true);
}

  

  

    
