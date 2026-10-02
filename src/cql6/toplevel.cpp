#include "node.h"
#include "attackarrowdirection.h"
#include "tokens.h"
/*the toplevel node grammar. 
  IMPORTANT: Keep in sync with grammar.txt!
  For basic named filters, see 
      matchcomplexnode.cpp
  For converting from grammar entities to set and numeric, see
       toplevel-aux.cpp
*/

Node* Tokens::match_node(){
  Node * left=match_or_x();
  if(!left) return NULL;
  while(match_keyword("or")){
    Node*right=match_or_x();
    if(!right)
      show_error("Missing right side of 'or'");
    left=new OrNode(left,right);
  }
  return left;
}


Node* Tokens::match_or_x(){
  Node * left=match_and_x();
  if(!left) return NULL;
  while(match_keyword("and")){
    Node*right=match_and_x();
    if(!right)
      show_error("Missing right side of 'and'");
    left=new AndNode(left,right);
  }
  return left;
}
  
Node* Tokens::match_and_x(){
  Node * left=match_in_x();
  if(!left) return NULL;
  if(!match_keyword("in"))
    return left;
  if(!left->isSet()&&!left->isString())
    show_error("left side of 'in' is not a set or a string");
  if (left->isSet()){
    SetBase* leftset=left->asSet();
    SetBase* rightset=match_set();
    if(!rightset)
      show_error("Cannot parse right side of 'in': not a set or not a filter");
    return new SubsetNode(leftset,rightset);
  }
  else if (left->isString()){
    Node*right=match_in_x(); //I have no idea what the correct way to handle this parsing is.
                             //hopefully if this fails it will do so clearly at compile time
    if (!right||!right->isString())
      show_error("Unable to obtain a filter from the right side of 'in' filter");
    return new StringInNode(left,right);
  }
  else
    show_error("The left side of an 'in' filter must be either a set filter or a string filter");
  return NULL;
}

Node* Tokens::match_in_x(){
  Node * left=match_relop_x();
  if(!left) return NULL;
  if(!left->isSet()&&!left->isPosition()&&!left->isNumeric()&&!left->isString()) return left;  
  string op=match_relationoperator();
  if(op.empty())return left;
  Node*right=match_in_x();
  if(!right)
    show_error("missing right side of relation operator: ",op);
  return make_relational_op_node(op,left,right);
}

Node*Tokens::match_relop_x(){
  Node*left=match_addop_x();
  if (!left)  return left;
  bool isstr=left->isString();
  bool iscount=left->isNumeric();
  if (!isstr&&!iscount)return left;
  uassert(isstr+iscount==1,"match_relop2_x type error");
  while(true){
    string op;
    int rightstart=save();
    if (isstr)
      op=match_plusoperator();
    else
      op=match_addoperator();
    if(op.empty())return left;
    if(op=="+" && left->isSequence())
      show_error("Attempt to add a 'line' filter to another filter. This is likely due to the last wildcard in the line filter being '+' and being interpreted as addition.\n If so, enclose the entire line filter in braces");
    Node*right=match_addop_x();
    if(!right)
      show_error("missing right side of operator: ",op);
    if (iscount && op=="+" && right->isString()){
      restore(rightstart);
      return left;
    }
    if (iscount&&!right->isNumeric()){
      show_error("when left side of arithmetic operator is numeric, right side must be too: ", op);
    }
    if(isstr&&op=="+"&&right->isNumeric()){
      restore(rightstart);
      return left;
    }
    if (isstr&&!right->isString())
      show_error("when left side of arithmetic operator is string, right side must be too: ", op);
    left=make_op_node(op[0],left,right);
  }
  return left;
}

Node*Tokens::match_addop_x(){
  Node*left=match_mulop_x();
  if(!left||!left->isNumeric())return left;
  while(true){
    string op=match_multoperator();
    if(op.empty())return left;
    if(op=="*" && left->isSequence())
      show_error("Attempt to multiply a 'line' filter by another filter. This is likely due to the last wildcard in the line filter being '*' and being interpreted as multiplication.\n If so, enclose the entire line filter in braces");
    Node*right=match_mulop_x();
    if(!right)
      show_error("missing right side of operator: ",op);
    if(!right->isNumeric())
      show_error("right side of operator is not numeric: ",op);
    left=make_op_node(op[0],left,right);
  }
  return left;
}


/*match_mulop is used for now in sequencematch.cpp, Tokens::match_holderconstituent
 this match_mulop_x() is also used in parsing # in Tokens::match_count_something()
 also used for parsing dashes in match_countmoves() and match_legaldash();
*/

Node*Tokens::match_mulop_x(){
  DashToken* baredashtoken=getDash();
  if(baredashtoken)return match_dashnode_from_prefix(NULL,baredashtoken);
  Node*leftnode=match_dash_tie_x();
  if(!leftnode||!leftnode->isSet()) return leftnode;
  int x=save();
  DashToken* dashtoken=getDash();
  if(!dashtoken || leftnode&&!dashtoken->isLeftTie()){
    restore(x);
    return leftnode;}
  /*now we have a dashtoken with a left tie. */
  return match_dashnode_from_prefix(leftnode->asSet(),dashtoken);
}

Node*Tokens::match_dash_tie_x(){
  Node*leftnode=match_attackarrow_x();
  if(!leftnode||!leftnode->isSet())return leftnode;
  AttackArrowDirection arrowdirection=match_attackarrow();
  if (AttackArrowDirectionIsInvalid(arrowdirection))
    return leftnode;
  vector<SetBase*>args;
  args.push_back(leftnode->asSet());
  while(true){
    Node*arg=match_attackarrow_x();
    if(!arg||!arg->isSet())
	show_error("unable to get right set argument to -> or <-");
    args.push_back(arg->asSet());
    if(!match_attackarrow(arrowdirection)) break;
  }
  uassert(args.size()>=2,"unexpected low length in match_dash_tie()");
  if(args.size()>2)
    return RayNode::makeFromAttackArrow(args,arrowdirection);
  uassert(args.size()==2,"attack arrow parse size ?");
  SetBase*left=args.at(0);
  SetBase*right=args.at(1);
  if(AttackArrowDirectionIsRight(arrowdirection))
    return new AttackNode(left,right,true,false);
  if(AttackArrowDirectionIsLeft(arrowdirection))
    return new AttackNode(right,left,false,true);
  uassert(false,"attack arrow eh?");
  return NULL;
}
      

Node*Tokens::match_attackarrow_x(){
  Node*left=match_union_x();
  if(!left||!left->isSet())return left;
  while(match_bar()){
    Node*right=match_union_x();
    if(!right)
      show_error("missing right side of operator: |");
    if(!right->isSet())
      show_error("right side of operator | is not a set filter: ");
    left=new UnionNode(left->asSet(),right->asSet());
  }
  return left;
}

Node*Tokens::match_union_x(){
  Node*left=match_intersect_x();
  if(!left)return NULL;
  if(!left->isSet()&&!left->isPosition())return left;
  while(match_ampersand()){
    Node*right=match_intersect_x();
    if(!right)
      show_error("missing right side of operator: &");
    if(left->isSet()&&right->isSet())
      left=new OnNode(left->asSet(),right->asSet());
    else if (left->isPosition()&&right->isPosition())
      left=new MatchNode(NULL, left,NULL, right);
    else
      show_error("right side of '&' does not match left side (they should both be either sets or positions)");
    uassert(left->isSet()||left->isPosition(),"mux internal");
  }
  return left;
}

Node* Tokens::match_intersect_x(){
  Node*left=match_attack_x();
  if(!left||!left->isSet())
    return left;
  while(true){
    bool seenattacks{false};
    bool seenattacked{false};
    if(match_keyword("attacks")||match_keyword("attack"))
      seenattacks=true;
    else if (match_keyword("attackedby")||match_keywords("attacked", "by"))
      seenattacked=true;
    else break;
    Node*right=match_attack_x();
    if(!right||!right->isSet())
      show_error("right side of 'attacks' or 'attackedby' is not a set filter");
    if (seenattacks)
      left=new AttackNode(left->asSet(),right->asSet(),true,false);
    else if (seenattacked)
      left=new AttackNode(right->asSet(), left->asSet(), false, true);
    else uassert(false,"attack parse internal");
  }
  return left;
}

Node*Tokens::match_attack_x(){ //changed in 9.301
  Node*left=match_substring_x();
  if (!left || !left->isString())return left;
  while(true){
    BracketRange*bracketrange=match_bracketrange();
    if(bracketrange&&left->isVariable()&&match_equalsign()){
      StringVariable *leftvar=left->asVariable()->asString();
      eassert(leftvar,"match_attack_x: difficulty parsing bracket following variable: ", leftvar->name);
      Node*right=match_string();
      if(!right) show_error("expecting a string following var[...]=");
      return new SubstringAssignmentNode(leftvar,bracketrange,right);
    }
    if (bracketrange)
      left=new SubstringNode(left,bracketrange);
    else if (match_tildetilde()){
      string rightstring;
      if(!match_quotedstringvalue(&rightstring))
	show_error(R"END(The right hand side of ~~ must be a string literal, e.g.
      x ~~ "h*llo")END");
      left=new StringMatchNode(left,rightstring);
    }//else if (match_tildetilde)
    else return left;
  } //while true
}
Node*Tokens::match_substring_x(){ //added in 9.301. used to be match_attack_x
  Node*left=match_with_x();
  if(!left || !left->isPosition())return left;
  if(!match_colon())return left;
  if(!left->isPosition())
    show_error("left side of ':' operator is not a position");
  Node*right=match_substring_x(); //modified from match_attack_x() in 9.301
  if(!right)
    show_error("could not get right hand side of operator ':'");
  return new WithPositionNode(left,right);
}

Node*Tokens::match_with_x(){
  return match_primitive();
}

/* match a primitive or match a dash operator that
   is just a bare dash (without a left tie). This is done
   for an obscure reason: to make the following parse work:

       x: -- check
  This also keeps : a higher precedence than left tie, so that
      x:y-- check
  is parsed we hope as
     {x:y}--check
  whether this all actually works is somewhat unclear. At best it is
  a highly dubious way to write this.
*/



Node*Tokens::match_primitive(){
  Node*n=NULL;
  DashToken*dash=dynamic_cast<DashToken*>(current());
  if(dash){
    n=match_mulop_x();
    if(!n)
      show_error("Unable to parse apparent -- operator");
  }
  if(!n) n=match_simplenode();
  if(!n) n=match_complexnode();
  return n;
}

  
  

