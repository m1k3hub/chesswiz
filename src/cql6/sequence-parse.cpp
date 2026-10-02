#include "node.h"
#include "tokens.h"

SequenceBase*Tokens::match_sequencenode(){
  bool is2{false};
  bool nestban{false};
  bool firstmatch{false};
  SeqDir direction{SeqDir::None};
  bool isprimary{false};
  bool issecondary{false};
  bool returnfinish{false};
  bool isquiet{false};
  Range*range{NULL};
  if(!match_keyword("line"))return NULL;
  while(true){
    if (match_keyword("singlecolor")){
      if(is2)show_error("multiple 'singlecolor' in 'line'");
      is2=true;
    }
    else if(match_keyword("primary")){
      if (isprimary||issecondary)
	show_error("multiple primary/secondary specifiers in line");
      isprimary=true;
    }
    else if (match_keyword("quiet")){
      if (isquiet)
	show_error("multiple 'quiet' specifiers in 'line'");
      isquiet=true;
    }
    else if (match_keyword("secondary")){
      if (isprimary||issecondary)
	show_error("multiple primary or secondary specifiers in line");
      issecondary=true;
    }
    else if (match_keyword("nestban")){
      if(nestban) show_error("multiple nestbans in 'line'");
      nestban=true;}
    else if (match_keyword("firstmatch")){
      if(firstmatch) show_error("multiple 'firstmatch' keywords in line");
      firstmatch=true;
    }
    else if (match_keyword("lastposition"))
      returnfinish=true;
    else if (!range&& ((range=match_range())))
      uassert(range,"msn internal range");
    else break;
  }
  if(match_rightarrow())
    direction=SeqDir::Future;
  else if (match_leftarrow())
    direction=SeqDir::Past;
  else
    show_error(
	       "Missing <-- or --> following line. Legal line syntaxes for example: \n"
	       "line --> check*\n"
	       "line --> move from K --> check --> R attacks n +"
	       );
  if (nestban&&direction==SeqDir::Past) //added 9.221 per bug report from Gamble 11/12/2019
    show_error("The 'nestban' parameter may not be used with backward line 'line <--'");
  vector<SeqConstituent*>constituents=match_seqconstituents(direction);
  if(constituents.empty())
    show_error("Could not get arguments to 'line'");
  if((isprimary||issecondary)&&direction==SeqDir::Past)
    show_error("'primary' and 'secondary' cannot be used with 'line<--'");
  SequenceBase* ret{NULL};
  if(direction==SeqDir::Future) ret = new FutureNode(constituents,range,is2,nestban,firstmatch,isprimary,issecondary,returnfinish,isquiet);
  else if(direction==SeqDir::Past) ret = new PastNode(constituents,range,is2,nestban,firstmatch,isprimary,issecondary,returnfinish,isquiet);
  else uassert(false,"msn dir");
  return ret;
}

vector<SeqConstituent*>Tokens::match_seqconstituents(SeqDir direction){
  uassert(seqdir_valid(direction),"mln arg");
  vector<SeqConstituent*>ret;
  SeqConstituent*current=match_seqconstituent(direction);
  if(!current)return ret;
  ret.push_back(current);
  while(true){
    bool leftarrow{false};
    bool rightarrow{false};
    if(match_leftarrow())leftarrow=true;
    else if(match_rightarrow()) rightarrow=true;
    else break;
    if(leftarrow&&direction!=SeqDir::Past ||
       rightarrow&&direction!=SeqDir::Future){
      show_error("arrow wrong direction in --> or <-- filter");
    }
    current=match_seqconstituent(direction);
    if(!current)
      show_error("Could not get filter following arrow in --> or <-- filter");
    ret.push_back(current);
  }//while true
  return ret;
}

SeqConstituent* Tokens::match_seqconstituent(SeqDir direction){
  uassert(seqdir_valid(direction),"msc dir");
  SeqConstituent*current=NULL;
  if(!current)current=match_vectorconstituent(direction);
  if(!current)current=match_holderconstituent(direction);
  if(!current) return NULL;
  return match_seqsuffix(current);
}

SeqConstituent* Tokens::match_seqsuffix(SeqConstituent*c){
  uassert(c,"stms");
  SeqConstituent*current=c;
  while(true){
    if(match_wildcardstar()){
      if(current->matchesNull())
	show_error("The '*' wildcard character cannot be used to apply to the requested expression, because that expression could match an empty sequence of positions");
      current=new StarConstituent(current);
    } // if _wildcardstar
    else if(match_wildcardplus()){
      if(current->matchesNull())
	show_error("The '+' wildcard character cannot be used to apply to the requested expression, because that expression could match an empty sequence of positions");
      if(dynamic_cast<PlusConstituent*>(current))
	show_error("The '+' wildcard character cannot be used to apply to another '+' wildcard expression, because the effect is the same as just using a single '+' wildcard");
      current=new PlusConstituent(current);
    }//if wildcardplus()
    else if (match_special("?")){
      if(current->matchesNull())
	show_error("The '?' wildcard character cannot be used to apply to the requested expression, because that expression could match an empty sequence of positions (so there is no point to using '?' here) ");
      current=new OptionalConstituent(current);
    }//if match_special("?")
    else {
      Range*range=match_repeat_range();
      if(!range) break;
      uassert(range->isConstant(),"internal bad nonconstantrange seqmatch");
      if(current->matchesNull()
	 || dynamic_cast<PlusConstituent*>(current))
	show_error("The {...} wildcard cannot be applied to an expression that matches an empty sequence of positions or to a '+' wildcard expression");
      current=new RepeatConstituent(current,range->getMin(),range->getMax());
    } // else
  }//while(true)
  return current;
}
  
//This expects either a non-lparen start OR a valid paren contained nonempty list of seqconstituent
VectorConstituent* Tokens::match_vectorconstituent(SeqDir direction){
  uassert(seqdir_valid(direction),"mvc args");
  vector<SeqConstituent*>args;
  if(!match_lparen())return NULL;
  args=match_seqconstituents(direction);
  if(args.empty())
    show_error("In --> or <-- filter: could not parse constituents of apparent vector constituent");
  if(!match_rparen())
    show_error("malformed expression inside --> or <-- filter: expected ')'");
  return new VectorConstituent(args,direction);
}

HolderConstituent* Tokens::match_holderconstituent(SeqDir direction){
  uassert(seqdir_valid(direction),"mhc args");
  Node*n=match_node(); 
  if(!n)return NULL;
  NumberNode*numbernode=dynamic_cast<NumberNode*>(n);
  NumericVariable*numvar=dynamic_cast<NumericVariable*>(n);
  ArithmeticNode*arithmeticnode=dynamic_cast<ArithmeticNode*>(n);
  if(numbernode){
    stringstream s;
    s<<"Attempt to create a line constituent from a single number: "<<
      numbernode->value;
    s<<". This is likely an error (perhaps the number was intended to part of a range). Try enclosing the desired filter in braces";
    show_error(s.str());}
  if(numvar){
    stringstream s;
    s<<"Attempt to create a line constituent from a single numeric variable: "<<numvar->name<<". This is likely an error. Try enclosing the desired filter in braces.";
    show_error(s.str());
  }
  if(arithmeticnode){
    stringstream s ;
    s<<"Attempt to create a line constituent from a binary arithmetic operation named: "
     <<arithmeticnode->namec<< '\n'
     << " Although tecnically legal, this is likely an error. "
     <<" \nMake sure that what you intended"
     <<" to be a wildcard character is not being parsed as an arithmetic operator\n"
     << "If so, try using braces to enclose the entire 'line filter' or each intended constituent\n"
     <<"You can also try using '{*}' and '{+}' instead of '*' and '+' for wildcards\n";
    show_error(s.str());
  }
  return new HolderConstituent(n);
}


/*matches {\d?(, \d?)?} with no spaces, as a token. 
  this fails to match old-style range like {2 4} or where
  there are space
*/

Range*Tokens::match_repeat_range(){
  BraceRepToken* bracerep = dynamic_cast<BraceRepToken*>(current());
  if(!bracerep)return NULL;
  forward();
  return new Range(bracerep->min,bracerep->max);
}

/* return the string character of +, * or ? if 
   a wildcard*/

/*This is used only by the old style sequence-parse methods. 
  Do not use for parsing path, as that is handled by lexer-cleanup files
  in the lexer now.
*/
string Tokens::match_wildcardcharacter(){
  int x=save();
  string name=match_special();
  if (name=="?") return name;
  if (name=="{+}") return "+";
  if (name=="{*}") return "*";
  if(name=="+" && at_wildcard_terminator())
    return "+";
  if(name=="*" && at_wildcard_terminator())
    return "*";
  restore(x);
  return "";
}

bool Tokens::at_wildcard_terminator(){
  int x=save();
  if (eof()||
      match_rbrace()||
      match_rparen()||
      match_rightarrow()||
      match_leftarrow()||
      match_repeat_range()||
      match_wildcardcharacter().size()
      ){
    restore(x);
    return true;}
  return false;
}
      
 
bool Tokens::match_wildcardplus(){
  int x=save();
  string w=match_wildcardcharacter();
  if(w=="+") return true;
  restore(x);
  return false;
}

bool Tokens::match_wildcardstar(){
  int x=save();
  string w=match_wildcardcharacter();
  if (w=="*") return true;
  restore(x);
  return false;
}
