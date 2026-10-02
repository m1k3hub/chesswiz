#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "nodeheaders.h"
SortNode* Tokens::match_sortnode(){
  if(!match_keyword("sort"))
    return NULL;
  SortDirection dir=SortDirection::None;
  bool isquiet=false;
  if (match_keyword("quiet")) //for now, the quiet must be the first parameter
    isquiet=true;
  if(match_keyword("min")){
    if(dir!=SortDirection::None)
      show_error("after 'sort' multiple 'min' or 'max' keywords seen");
    dir=SortDirection::Up;
  }
  else if (match_keyword("max")){
    if(dir!=SortDirection::None)
      show_error("after 'sort' multiple 'min' or 'max' keywords seen");
    dir=SortDirection::Up;
  }
  if (match_keyword("quiet"))
    show_error("'quiet' must be the first parameter to 'sort'. Possible out-of-order parameter 'quiet' following 'sort' detected"); //check for 'sort min quiet' just to simplify parsing which is hard enough here
  string doc=match_nonemptyquotedstring();
  if (doc.empty()&& (dir!=SortDirection::None))
    show_error("When 'max' or 'min' is explicitly specified following 'sort', you must include a nonempty documentation string following. For example 'sort min \"npieces\".... This helps reduce the chance of confusion between 'max' or 'min' as a sort keyword and as a function");
  if(doc.empty()){
    stringstream s;
    environment->sortId++;
    s<<"<sort-id-"<< environment->sortId<<">";
    doc=s.str();
  }
  if(dir==SortDirection::None)
    dir=SortDirection::Down;
  Node*filter=match_node();
  if (!filter||(!filter->isNumeric()&&!filter->isSet()&&!filter->isString()))
    show_error("Unable to get numeric or set filter or string filter in argument to 'sort'");
  NumberNode*nn=dynamic_cast<NumberNode*>(filter);
  if(nn!=NULL){
    stringstream s;
    s<<"Following 'sort' saw a number with value: "<<nn->toString();
    s<<" Although not illegal, this is likely an error (ranges are no longer supported in 'sort')";
    show_error(s.str());
  }
  Node*passedfilter=NULL;
  if (filter->isSet()){
    uassert(!filter->isNumeric()&&!filter->isString(),"match_sortnode multiple class");
    passedfilter=new CountSquaresNode(filter->asSet());
  }
  else if (filter->isNumeric())
    passedfilter=filter;
  else if (filter->isString())
    passedfilter=filter;
  else
    uassert(false,"unable to get type of argument to 'sort', internal error");
  filter=NULL;
  //handle echonode specially. Should recursively do this on all children
  for (auto child:passedfilter->descendants()){
    EchoNode*echonode=dynamic_cast<EchoNode*>(child);
    if(echonode){
      if (dir!=SortDirection::Down)
	show_error("min sorting is not supported with an echo filter");
      echonode->setIsSort();
    }
  }
  uassert(passedfilter->isSortable(),"Expected a numeric or string filter following 'sort'");
  return new SortNode(environment,doc,dir,isquiet,passedfilter); //make sure order is right!
}


