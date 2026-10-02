#include "node.h"
#include "sortnode.h"
#include "numericvariable.h"
#include "sortvariable.h"
#include "environment.h"

string SortNode::prefix(){
  return string("_CQLSORT_");
}

SortNode::SortNode(Environment*environment,string doc, SortDirection dir, bool isquiet, Node*filter):
  documentation(doc),
  isQuiet(isquiet),
  theFilter(filter),
  theDirection(dir)
{
  uassert(environment&&documentation.size()&&theFilter&&theFilter->isSortable(),"SortNode args");
  uassert(isMax()||isMin(),"snsn maxmin");
  if (theFilter->isNumeric()) theSortValueType=SortValueType::Numeric;
  else if (theFilter->isString())theSortValueType=SortValueType::String;
  else uassert(false,"invalid filter type in sortnode::sortnode()");
  string varname=prefix()+documentation; //change this later per Gamble convention
  Variable* v=environment->find(varname);
  if(v){
    uassert(v->isSort(),"in SortNode, expected a sortable variable: ",varname);
    theVariable=v->asSortVariable();
    uassert(v->isString()==isString()&&v->isNumeric()==isNumeric(),"sortnode: bad variable type");
    uassert(theVariable&&theVariable->isUnbound(),"in SortNode, expected an unbound variable", theVariable->name);
  }
  else{
    if (isNumeric())
      theVariable=environment->createNumericVariable(varname);
    else
      theVariable=environment->createStringVariable(varname);
    environment->registerSortVariable(theVariable,getDirection());
    if (isQuiet) environment->setQuietSortVariable(theVariable);
  }
  uassert(theVariable
	  &&theVariable->isUnbound(),
	  "sortnode variable create: ",theVariable->name);
  uassert(theVariable->isString()==isString()&&theVariable->isNumeric()==isNumeric(),"sortnode bad vartype");
}
    
bool SortNode::match_position(QPos*qpos){
  SortValue val(getSortValueType(), getDirection());
  return match_sortvalue(qpos,&val);
}

//For now this does not change the variable binding/unbinding code, which seems to work
void SortNode::clear(){
  commentStack.clear();
  qgame=NULL;
  commentValue.clear();
  gamenumber=0;
}

bool SortNode::match_sortvalue(QPos*qpos,SortValue*sortvaluep){
  if(!qgame){
    qgame=qpos->qgame;
    gamenumber=qgame->getGameNumber();
  }
  else
    uassert(qgame==qpos->qgame&&gamenumber==qpos->qgame->getGameNumber(),"sortnode bad sync");
  int x=qpos->markComments();
  if(match_filtersortvalue(theFilter,qpos,sortvaluep)){
    handle_new_value(*sortvaluep,x);
    return true;
  }
  qpos->restoreComments(x);
  return false;
}

bool SortNode::match_filtersortvalue(Node*node,QPos*qpos, SortValue*sortvalue){
  if (node->isNumeric()){
    NumValue numvalue=0;
    if(node->match_count(qpos,&numvalue)){
      sortvalue->bind(numvalue);
      return true;
    }
    return false;
  }//node->isString()
  else if (node->isString()){
    string stringvalue;
    if (node->match_stringvalue(qpos,&stringvalue)){
      sortvalue->bind(stringvalue);
      return true;
    }
    return false;
  }//node->isString()
  uassert(false,"invalid node type in sortnode");
  return false;
}
      
bool SortNode::match_count(QPos*qpos,NumValue*v){
  SortValue value(SortValueType::Numeric, getDirection());
  if (match_sortvalue(qpos,&value)){
    *v=value.getNumericValue();
    return true;
  }
  return false;
}

bool SortNode::match_stringvalue(QPos*qpos,string *stringp){
  SortValue value(SortValueType::String, getDirection());
  if (match_sortvalue(qpos,&value)){
    *stringp=value.getStringValue();
    return true;
  }
  return false;
}

/* In the below, commentValue is the best value seen so far by this node, as long
as comments are set. This might be strictly worse than the value of theVariable, which
is shared with other SortNode instances arising from transforms (or indeed the same
documentation string being reused. */


void SortNode::handle_new_value(SortValue value, int top){
  uassert(qgame,"sn hnv internal");
  SortValue current(getSortValueType(),getDirection());
  theVariable->assignSortValue(&current);
  if (current < value){
    theVariable->bindSortValue(value);
    if(CqlSortComments){
      CommentStack* mainstack=qgame->getCommentStack();
      uassert(top>=0&&top<=mainstack->size(),"sortnode top error");
      commentStack.clear();
      mainstack->transfer(top,&commentStack);
      commentValue=value;
    }
  }
  else
    if(CqlSortComments)qgame->restoreComments(top);
}

/* When makeComments() is called, commentValue() is the best value seen so far. It might
be strictly worse (less) than the value of theVariable but should never be greater. See
comments to handle_new_value*/


void SortNode::makeComments(){
  if(!CqlSortComments){
    uassert(commentStack.empty(),"snmc nsort");
    return;
  }
  if(commentStack.empty())return;
  uassert(qgame&&gamenumber==qgame->getGameNumber(),"sn mc internal");
  uassert(theVariable->isBound(),"sortnode: variable unexpectedly unbound: ",theVariable->name);
  SortValue current(getSortValueType(),getDirection());
  theVariable->assignSortValue(&current);
  if (current<commentValue){
    cout<<"SortNode: bad comment/current value. commentValue is: "<<
      commentValue.toString()
	<<" currentvalue is: "
	<<current.toString()
	<<" gamenumber: "<<gamenumber<<endl;
  }
  uassert(!(current<commentValue), "SortNode::makeComments: current issue");
  if(commentValue<current) return; //another SortNode found a better value to use
  CommentStack*mainstack=qgame->getCommentStack();
  uassert(commentStack.size()>0,"sn mc top error");
  commentStack.transfer(0,mainstack);
}
  
  
vnode SortNode::children()const{
  vnode ret{theFilter};
  if (theVariable!=theFilter) ret.push_back(theVariable);
  return ret;
}

void SortNode::deepify(){
  theFilter=theFilter->clone();
  uassert(theVariable->isUnbound(),"SortNode::deepify");
}

string SortNode::convertName(const string&varname){
  if(varname=="matchcount") return "matchcount";
  string pre=prefix();
  auto prelen=pre.size();
  uassert(varname.size()>pre.size(),"sortnode getname bad varname");
  uassert(pre==varname.substr(0,prelen),"sortnode getname prefix mismatch: ",varname);
  string ret=varname.substr(prelen);
  uassert(ret.size()==varname.size()-prelen,"sortnode getname size");
  return ret;
}

/*I have no idea what this is here for. */
bool operator< (const SortNode& lhs, const SortNode& rhs){
  uassert(false,"sno< should not be callsed'");
  return false;
}




