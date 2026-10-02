#include "token.h"
#include "node.h"
#include "tokens.h"
#include "pathnode.h"
#include "focus.h"


PathNode*Tokens::match_pathnode(){
  bool is2{false};
  bool nestban{false};
  bool firstmatch{false};
  bool isprimary{false};
  bool returnfinish{false};
  bool usepiecepath{false};
  string title;
  bool isverbose{false};
  bool isquiet{false};
  Focus* focus{NULL};
  Node* themax{NULL};
  bool keepallbest{false};
  Range*range{NULL};
  if(!match_keyword("path"))return NULL;
  while(true){
    if (match_keyword("singlecolor")){
      if(is2)show_error("multiple 'singlecolor' in 'path'");
      if(focus)show_error("'singlecolor' cannot be used with 'focus'");
      is2=true;
    }
    else if (match_keyword("max")){
      if(themax)
	show_error("multiple 'max' specifications in 'path' specification");
      themax=match_node();
      if(!themax)
	show_error("missing filter following 'path max'");
    }
    else if(match_keyword("verbose")){
      if(isverbose)
	show_error("multiple 'verbose' paramters in  'path'");
      isverbose=true;
    }
    else if (match_keyword("title")){
      title=match_nonemptyquotedstring();
      if(!title.size())
	show_error("expected nonempty quoted string following 'title' parameter to 'path'");
    }
    else if (match_keyword("keepallbest")){
      if(keepallbest)
	show_error("multiple 'keepallbest' parameters in 'path'");
      keepallbest=true;
    }
    else if (match_keyword("focus")){
      CaptureType focuscapturetype{CaptureType::NonCapture};
      if(is2)show_error("'focus' cannot be used when 'singlecolor' is used");
      if (focus)
	show_error("multiple 'focus' parameters in 'path'");
      if (match_keyword("capture")) focuscapturetype=CaptureType::Capture;
      SetBase*fset=match_set();
      if(!fset)
	show_error("could not parse filter that should follow keyword 'focus' or 'focus capture' in 'path'");
      focus=new Focus(fset,focuscapturetype);
    }
    else if(match_keyword("primary")){
      if (isprimary)
	show_error("multiple primary specifiers in path");
      isprimary=true;
    }
    else if (match_keyword("piecepath")){
      if(usepiecepath)
	show_error("multiple piecepath parameters in path");
      usepiecepath=true;
    }
    else if (match_keyword("quiet")){
      if (isquiet)
	show_error("multiple 'quiet' specifiers in 'path'");
      isquiet=true;
    }
    else if (match_keyword("secondary")){
      show_error("the 'secondary' keyword is not supported with 'path'");
    }
    else if (match_keyword("nestban")){
      if(nestban) show_error("multiple nestbans in 'path'");
      nestban=true;}
    else if (match_keyword("firstmatch")){
      if(firstmatch) show_error("multiple 'firstmatch' keywords in path");
      firstmatch=true;
    }
    else if (match_keyword("lastposition"))
      returnfinish=true;
    else if (!range&& ((range=match_range())))
      uassert(range,"msn internal range");
    else break;
  }
  if (is2) {
    uassert(focus==NULL,"unexpected non-null focus and singlecolor");
    SetBase*scn=set_from_string("if wtm A else a");
    uassert(scn,"path-parse is2");
    focus=new Focus(scn,CaptureType::NonCapture);
  }
  if(usepiecepath){
    if(!focus)
      show_error("the 'piecepath' parameter to 'path' can only be used when the 'focus' option specifies a focus, since the piecepath parameter indicates that moves in focus are specially commented. No 'focus' option was specified.");
  }
  if(focus&&isprimary){
    const string messagestring=
      R"E(Although legal, the implementation does not currently support use of 
          the keywords 'focus' and 'primary' as parameters to the same 'path'. 
          You can manually simulate the effect by using
                 pathstart:depth==depth
           as a path constituent.
          For example, instead of
               path focus A primary
                   Q-- check {5,}
           (which finds at least 5 consecutive primary white queen checks), use
          path focus A
                  Q-- check {5,}
                  pathstart:depth==depth
         )E";

    show_error(messagestring);
  }
  vector<PathCon*>cons=match_pathcons();
  if(cons.empty())
    show_error("Could not get arguments to 'path'");
  if(current()&&current()->isEndPathToken())
    forward();
  cons.front()->setIsInitial(); //must come after setting the focus, which does not adjust initial setting.
  vector<Variable*>atomicvariables=environment->getAtomicVariables();
  return new PathNode(cons
		      ,range
		      ,focus
		      ,nestban
		      ,firstmatch
		      ,isprimary
		      ,returnfinish
		      ,themax
		      ,atomicvariables
		      ,usepiecepath
		      ,isquiet
		      ,title
		      ,isverbose
		      ,keepallbest);
}

vector<PathCon*>Tokens::match_pathcons(){
  vector<PathCon*>ret;
  while (true){
    PathCon*pc=match_pathcon();
    if(!pc)return ret;
    ret.push_back(pc);
  }
  return ret;
}

      

/*given a stack of cons matched so far, match the next constituent and push
  it onto the stack. For a wildcard, pop all the arguments to that wildcard 
  as well. return true if a match was made*/

PathCon* Tokens::match_pathcon(){
  if(!current())return NULL;
  if(current()->isEndPathToken())
      return NULL;
  PathCon*currcon=NULL;
  if(!currcon)currcon=match_chaincon();
  if(!currcon)currcon=match_dashcon();
  if(!currcon)currcon=match_holdercon();
  if(!currcon) return NULL;
  currcon=add_wildcard(currcon);
  return currcon;
}

/*read the next token. If it is not a wildcard, return argument. 
  Otherwise, apply wildcard to pathcon and return new PathCon
*/
PathCon*Tokens::add_wildcard(PathCon* pathcon){
  uassert(pathcon,"pctaw");
  if(pathcon->isHolderCon())return pathcon;
  if(!(pathcon->isChainCon()||pathcon->isDashCon())){
    cout<<"Bad pathcon type add_wildcard [path-parse.cpp]"<<endl;
    cout<<"Actual pathcon is: "<<endl;
    pathcon->print();
  }
  uassert(pathcon->isChainCon()||pathcon->isDashCon(),"pctaw wrong pathcon type");
  Token*wildcard=read_wildcard();
  if(!wildcard)return pathcon;
  Token*nextwildcard=read_wildcard();
  if(nextwildcard){
    stringstream s;
    s<<"Two consecutive wildcards detected: "
     <<wildcard->toString()
     <<" and "
     <<nextwildcard->toString()
     <<" this is not supported at this time.";
    show_error(s.str());
  }

  return create_wildcard_node(pathcon,wildcard);
}

ChainCon* Tokens::match_chaincon(){
  vector<PathCon*>args;
  if(!match_lparen())return NULL;
  args=match_pathcons();
  if(args.empty())
    show_error("In path filter: could not parse constituents of apparent chain constituent");
  if(!match_rparen())
    show_error("malformed expression inside path filter: expected ')'");
  return new ChainCon(args);
}

HolderCon* Tokens::match_holdercon(){
  int x=save();
  Node*n=match_node(); 
  if(!n)return NULL;
  /*We can see a spurious dashnode when an DashCon calls match_holdercon() to try and find its targets*/
  if (n->isDashNode()){
    restore(x);
    return NULL;
  }
  NumberNode*numbernode=dynamic_cast<NumberNode*>(n);
  NumericVariable*numvar=dynamic_cast<NumericVariable*>(n);
  ArithmeticNode*arithmeticnode=dynamic_cast<ArithmeticNode*>(n);
  if(numbernode){
    stringstream s;
    s<<"Attempt to create a path constituent from a single number: "<<
      numbernode->value;
    s<<". This is likely an error (perhaps the number was intended to part of a range). Try enclosing the desired filter in braces";
    show_error(s.str());}
  if(numvar){
    stringstream s;
    s<<"Attempt to create a path constituent from a single numeric variable: "<<numvar->name<<". This is likely an error. Try enclosing the desired filter in braces.";
    show_error(s.str());
  }
  if(arithmeticnode){
    stringstream s ;
    s<<"Attempt to create a path constituent from a binary arithmetic operation named: "
     <<arithmeticnode->namec<< '\n'
     << " Although tecnically legal, this may be an error. "
     <<" \nMake sure that what you intended"
     <<" to be a wildcard character is not being parsed as an arithmetic operator\n"
     << "If so, try using braces to enclose the entire 'path filter' or each intended constituent\n"
     <<"You can also try using '{*}' and '{+}' instead of '*' and '+' for wildcards\n";
    show_error(s.str());
  }
  return new HolderCon(n);
}

  
/*roughly in sync with Tokens::match_with_x in toplevel.cpp and match_dashnode_from_prefix. 
  the main difference is here there is no target

  This works as follows:
  First, we match --. If we get this, we invoke match_dashcon_from_prefix and return the result.
  Otherise, if we have an dash, it must be a left tie. So we try and match a left set by
  matching a primitive and seeing if it is a set. If we cannot match a primitive or if the primitive
  is not a set, we return NULL. If we can matcha primitive, we try and match -- and invoke
  match_dashcon_from_prefix again.

  four cases:
  no-tie dash no tie
  no-tie dash tie set
  set tie dash notie
  set tie dash tie set
*/


/* return an dashcon but without matching any targets. This is roughly in sync with
   tokens::match_with_x in toplevel.cpp and math_dasnode_from_prefix. the difference here
   is that just the left, right, and type are returned
*/

DashCon*Tokens::match_dashcon(){
  int x=save();
  DashCon*bare=match_ignoreleft_dashcon();
  if(bare) return bare;
  Node*leftnode=match_dash_tie_x();
  if(!leftnode||!leftnode->isSet()){
    restore(x);
    return NULL;
  }
  bool haslefttie=left_tie_follows();
  if(!haslefttie){
    restore(x);
    return NULL;
  }
  bare=match_ignoreleft_dashcon();
  if(!bare)
    show_error("Internal parser error in attempting to parse a DashCon: expected a DashCon here");
  bare->setLeft(leftnode->asSet());
  return bare;
}

/*match a dashcon but starting from the dashcon itself. The left argument will
  be added later if necessary*/

DashCon*Tokens::match_ignoreleft_dashcon(){
  DashToken*dashtoken=getDash();
  if(!dashtoken)return NULL;
  SetBase*right{NULL};
  Node*promotionnode{NULL};
  if(dashtoken->isRightTie()){
    right=match_dash_right();
    promotionnode=match_dash_promotion();
  }
  Node* target=match_dashcon_target();
  if(promotionnode&&!target)
    target=promotionnode;
  else if (promotionnode)
    target=new AndNode(promotionnode,target);
  return new DashCon(NULL,right,target,dashtoken->getCaptureType());
}

Node*Tokens::match_dashcon_target(){
  vector<Node*>targets;
  HolderCon*holder;
  while(true){
    holder=match_holdercon();
    if(!holder)break;
    targets.push_back(holder->getFilter());
  }
  if (targets.empty())return NULL;
  if (targets.size()==1)return targets.back();
  return new CompoundNode(targets);
}

Token* Tokens::read_wildcard(){
  Token*ret=current();
  if(!ret)return NULL;
  if(!ret->isWildcardToken())return NULL;
  forward();
  return ret;
}
   
PathCon*Tokens::create_wildcard_node(PathCon*pathcon, Token*wildcard){
  uassert(wildcard&&wildcard->isWildcardToken(),"pctcwn eh?");
  bool isstar=wildcard->isWildcardStarToken();
  bool isplus=wildcard->isWildcardPlusToken();
  bool isquestion=wildcard->isQuestionMarkToken();
  bool isbracerep=wildcard->isBraceRepToken();
  BraceRepToken*bracerep=dynamic_cast<BraceRepToken*>(wildcard);
  if(isbracerep)uassert(bracerep,"pctcwn br");
  uassert(isstar+isplus+isquestion+isbracerep==1,
	  "pctcwn internal bad type in wildcard");
  if(isstar)return new StarCon(pathcon);
  if(isplus)return new PlusCon(pathcon);
  if(isquestion)return new OptionalCon(pathcon);
  if(bracerep)return new RepeatCon(pathcon,bracerep->min,bracerep->max);
  uassert(false,"pctcwn huh?");
  return NULL;
}

bool Tokens::left_tie_follows(){
  DashToken*dashtoken=dynamic_cast<DashToken*>(current());
  if(!dashtoken)return false;
  return dashtoken->isLeftTie();
}
