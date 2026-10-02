#include "node.h"
#include "tokens.h"
#include "movebase.h"
#include "environment.h"
#include "nonemptynode.h"
#include "commentnode.h"

Node* Tokens::match_movebase(){ //misnamed actually since MoveLegalNode is not a movebase
  bool past{false}; // previous
  bool future{false}; // future or none
  bool legal=false; // legal
  bool pseudolegal=false; // pseudolegal
  bool isfrom{false}; // from is first seen
  bool isto{false}; // to is first seen
  bool iscapture{false};//capture is first seen
  bool nullmove{false}; // nullmove
  bool primaryMove{false}; // primary
  bool secondaryMove{false}; // secondary
  int keywordindex{0};
  Range* range{NULL}; // will go away soon
  SetBase* captureNode{NULL}; // capture
  PieceLoc* promote{NULL}; //promote
  SetBase* epcapture{NULL}; //enpassantsquare
  SetBase*fromNode{NULL}; 
  SetBase*toNode{NULL};   
  SetBase * fromcastle{NULL};
  SetBase* tocastle{NULL};
  CommentNode* commentnode{NULL};
  
  if (!match_keyword("move")) return NULL;

  while(++keywordindex>0){
    if (false); 
    else if (match_move_capture(&captureNode)){
      if(keywordindex==1)iscapture=true;
    }
    else if (match_move_castle(&fromcastle, &tocastle));
    else if (match_keyword("count"))
      range=new Range(0, 1000);
    else if (match_move_enpassant(&epcapture));
    else if (match_move_from(&fromNode)){
      if (keywordindex==1) isfrom=true;
    }
    else if (match_keyword("legal"))
      legal=true;
    else if (match_keyword("null"))
      nullmove=true;
    else if (match_keyword ("previous"))
      past=true;
    else if (match_keyword("primary"))
      primaryMove=true;
    else if (match_move_promote(&promote));
    else if (match_keyword("pseudolegal"))
      pseudolegal=true;
    else if (match_keyword("secondary"))
      secondaryMove=true;
    else if (match_move_to(&toNode)){
      if(keywordindex==1) isto=true;
    }
    else break;
  }//while(true); 
  //All the keywords except comment have now been parsed. Now parse the arguments.
  //Start by checking is the current keyword is a comment:
  int commentstart=save();
  if (!legal&&!pseudolegal&&match_keyword("comment")){
    restore(commentstart);
    commentnode=dynamic_cast<CommentNode*>(match_stringconverter());
    uassert(commentnode && !commentnode->theIsMessage,
	    "In parsing a 'comment' keyword to 'move', an internal error B94 was reached");
  }
  if (!legal && !past &&!pseudolegal) future=true;
  if (range&&!legal&&!pseudolegal)
    show_error("the 'count' keyword in 'move' can only be used when 'legal' or 'pseudolegal' are also specified");
  if(isto) uassert(toNode,"moveparse to");
  if (isfrom) uassert(fromNode,"moveparse from");
  if(iscapture)uassert(captureNode,"moveparse capture");
  if(!fromNode)fromNode=new AnyNode();
  if(!toNode)toNode=new AnyNode();
  //Add in the castling...
  uassert(fromNode&&toNode,"mmm move ft");
  uassert((fromcastle==NULL)==(tocastle==NULL), "mm fc tc null");
  if (fromcastle)
    {fromNode= new OnNode(fromNode,fromcastle);
      toNode= new OnNode(toNode,tocastle);
    }
  //all the arguments have been parsed. So we now  just check for consistency:
  uassert(legal+past+future+pseudolegal>0,"move parsing error: unexpected match keyword failure");
  if (legal + past + future +pseudolegal> 1)
    show_error("After 'move' cannot specify both 'legal' or 'pseudolegal' and 'previous'");
  if ((legal || pseudolegal) && (promote || primaryMove || nullmove || secondaryMove))
    show_error("cannot use the following keywords with 'move legal' or 'move pseudolegal': 'null', 'primary', 'secondary', or 'promote'");
  if (nullmove&&(promote||epcapture||legal||pseudolegal))
    show_error("cannot use null with 'from', 'to', 'promote', 'legal', 'pseudolegal', or 'enpassant'");
  if(epcapture&&promote)
    show_error("cannot have a move that is both an en passant capture and a promotion");
  uassert(fromNode&&toNode,"match_movebase from / to");
  uassert(isfrom+isto+iscapture<=1,"isfrom/isto mismatch in match_movebase");
  if(captureNode&& (legal||pseudolegal))
    show_error("the 'capture' keyword is not currently supported in conjunction with 'legal' or 'pseudolegal'");
  SetBase*baseset{NULL};
  bool passedisto{isto};
  bool passedisfrom{isfrom};
  bool passediscapture{iscapture};
  if(!passedisto&&!passedisfrom&&!passediscapture) passedisto=true; //the constructors are expecting one of these to be true
  if (past)
    baseset= new MovePastNode(fromNode,toNode,promote,epcapture,captureNode,commentnode,nullmove,primaryMove,secondaryMove,passedisfrom,passedisto,passediscapture);
  else if(future)
    baseset= new MoveFutureNode(fromNode,toNode,promote,epcapture,captureNode,commentnode,nullmove,primaryMove,secondaryMove,passedisfrom,passedisto,passediscapture);
  else if (legal || pseudolegal){
    baseset =new MoveLegalNode(fromNode,toNode,epcapture,range,pseudolegal,passedisfrom,passedisto);
  }
  uassert(baseset,"moveparse baseset");
  if(isfrom||isto||iscapture||!baseset->isSet())
    return baseset;
  return new NonemptyNode(baseset);
}

bool Tokens::match_move_promote(PieceLoc**promotep){
  uassert(promotep,"mmp arg");
  if(!match_keyword("promote")) return false;
  if(*promotep)
    show_error("multiple 'promote' designators in 'move'");
  PieceLoc* p=match_pieceloc();
  if(!p) show_error("missing piece designator following 'promote'");
  if(!p->isPurePiece())
    show_error("The promoted piece must be just a piece or set of pieces without square designators, e.g. 'promote R' or 'promote [RN]' ");
  return *promotep=p;
  return true;
}

bool Tokens::match_move_enpassant(SetBase**epsquarep){
  uassert(epsquarep,"mme ep");
  if (match_keyword("enpassant")){
    if (*epsquarep)
      show_error("multiple enpassant expressions in 'move'");
    *epsquarep=new AnyNode();
    return true;
  }
  else  if  (match_keyword("enpassantsquare")){
    if(*epsquarep)
      show_error("multiple enpassant/enpassantsquare expressions in 'move'");
    SetBase* set=match_setparameter();
    if(!set)
      show_error("missing set filter following 'enpassantsquare'");
    *epsquarep=set;
    return true;
  }
  return false;
}

bool Tokens::match_move_capture(SetBase**capturep){
  uassert(capturep,"mmc c");
  if (!match_keyword("capture")&&!match_keyword("captures"))return false;
  SetBase*set=match_setparameter();
  if(!set)
    show_error("missing set filter following 'capture'");
  *capturep=set;
  return true;
}

bool Tokens::match_move_castle(SetBase**fromp, SetBase**top){
  uassert(fromp&&top,"mmc f t");
  if (match_keyword("o-o")){
    if(*fromp || *top)
      show_error("multiple castling specifications in 'move'");
    SetBase*from=new NoTransformNode(set_from_string("Ke1 | ke8"));
    SetBase*to=new NoTransformNode(set_from_string ("g1 | g8"));
    uassert(from&&to,"mmc from to");
    *fromp=from;
    *top=to;
    return true;
  }
  else if (match_keyword("o-o-o")){
    if(*fromp || *top)
      show_error("multiple castling specifications in 'move'");
    SetBase* from=new NoTransformNode(set_from_string("Ke1 | ke8"));
    SetBase* to=new NoTransformNode(set_from_string("c1 | c8"));
    uassert(from&&to,"mmcooo from to");
    *fromp=from;
    *top=to;
    return true;
  }
  else if (match_keyword("castle")){
    if(*fromp || *top)
      show_error("multiple castling specifications in 'move'");
    SetBase* from=new NoTransformNode(set_from_string("Ke1 | ke8"));
    SetBase* to = new NoTransformNode(set_from_string("g1 | g8 | c1 | c8"));
    uassert(from&&to,"mmcc from to");
    *fromp=from;
    *top=to;
    return true;
  }
  return false;
}
    
bool Tokens::match_move_from(SetBase**fromp){
  if(!match_keyword("from"))return false;
  uassert(fromp,"mmf from");
  if(*fromp)
    show_error("'from' apparently used twice in 'move'");
  SetBase* from=match_setparameter();
  if(!from)
    show_error("Expected a set filter following 'from' in move filter");
  *fromp=from;
  return true;
}

bool Tokens::match_move_to(SetBase**top){
  if(!match_keyword("to"))return false;
  uassert(top,"mmf to");
  if(*top)
    show_error("'to' apparently used twice in 'move'");
  SetBase* to=match_setparameter();
  if(!to)
    show_error("Expected a set filter following 'to' in move filter");
  *top=to;
  return true;
}
