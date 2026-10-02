#include "environment.h"
#include "variable.h"
#include "sortvariable.h"
#include "pieceidvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "transformvariable.h"
#include "lambdavariable.h"
#include "dictionary.h"
#include "atomic.h"

vector<SortVariable*>* Environment::getSortVariables(){
  return &theSortVariables;
}

Variable* Environment::find(string nm)const{
  for(Variable* v:theVariables){
    uassert(v,"Find found NULL variable while seeking value: ",nm);
    if (v->eq(nm))
      return v;
  }
  return NULL;
}

void Environment::registerVariable(Variable*v){
  uassert(v,"registerVariable internal");
  uassert(myindex(theVariables,v)<0,"registerVariable: double include");
  theVariables.push_back(v);
}


Variable* Environment::createVariable(string name, ValueType vtype, bool ispersistent, string&errormessage){
  uassert(name.size(),"ecv name");
  uassert(!find(name),"ecv: variable already exists");
  Variable*v{NULL};
  stringstream s;
  switch(vtype){
  case ValueType::Number:
    v=createNumericVariable(name);
    break;
  case ValueType::String:
    v=createStringVariable(name);
    break;
  case ValueType::Set:
    v=createSquareVariable(name);
    break;
  case ValueType::Position:
    v=createPositionVariable(name);
    break;
  default:
    s<<"Cannot create variable "<<name
     <<" with value of type "<<Node::valuetypeToString(vtype);
    goto fail;
  }//switch(vtype);
  uassert(v,"ecv internal switch");
  if (ispersistent&& !Node::valuetypeIsPersistent(vtype)){
    s<<"Only string, set, and numeric variables can be persistent: "<< name;
    goto fail;
  }
  if (ispersistent)v->setPersistent();
  return v;
 fail:
  errormessage=s.str();
  return NULL;
}
    
    
NumericVariable* Environment::createNumericVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createNumeric: exists: ",name);
  auto v=new NumericVariable(name);
  registerVariable(v);
  return v;
}

StringVariable* Environment::createStringVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createString: exists: ",name);
  auto v=new StringVariable(name);
  registerVariable(v);
  return v;
}

PositionVariable* Environment::createPositionVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createPositionVariable: exists: ",name);
  auto v=new PositionVariable(name);
  registerVariable(v);
  return v;
}

TransformVariable* Environment::createTransformVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createTransformVariable: exists: ",name);
  auto v=new TransformVariable(name);
  registerVariable(v);
  return v;
}

SquareVariable* Environment::createSquareVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createSquare: exists: ",name);
  auto v=new SquareVariable(name);
  registerVariable(v);
  return v;
}

Dictionary* Environment::createDictionary(string name,bool ispersistent){
  uassert(name.size(),"ecd null name");
  uassert(!find(name),"createDictionary: exists: ",name);
  Dictionary* d=new Dictionary(name,ispersistent);
  registerVariable(d);
  if(d->isPersistent())
    setQuietPersistentVariable(d);
  return d;
}

PieceIdVariable* Environment::createPieceIdVariable(string name){
  uassert(name.size(),"cnv internal name");
  uassert(!find(name),"createPieceId: exists: ",name);
  auto v=new PieceIdVariable(name);
  registerVariable(v);
  return v;
}

LambdaVariable* Environment::createLambdaVariable(string name, LambdaValue lambda){
  uassert(name.size(),"vclv name");
  uassert(!find(name),"createLambdaVariable: variable of same name exists: ",name);
  auto v = new LambdaVariable(name,lambda);
  registerVariable(v);
  return v;
}

void Environment::unbindPieceIds(){
  for(Variable* v : theVariables){
    PieceIdVariable* tv=dynamic_cast<PieceIdVariable*>(v);
    if(tv&&tv->bound){
      tv->unbind();
      uassert(!tv->isBound(),"vut: unbound variable");
    }
  }
}

//return a variable with the name "matchcount" or create if necessary
NumericVariable* Environment::matchCountVariable(){ 
  auto var=find("matchcount");
  NumericVariable*nvar=NULL;
  if (var){
    nvar=dynamic_cast<NumericVariable*>(var);
    uassert(nvar,"matchcount variable of wrong type");
  }
  else nvar=createNumericVariable("matchcount");
  uassert(nvar,"matchcountvar");
  return nvar;
}

void Environment::registerSortVariable(SortVariable*sortvar,SortDirection dir){
  uassert(sortvar,"registerSortVariable: arg");
  uassert(dir==SortDirection::Up||dir==SortDirection::Down,"rsv dir");
  uassert(myindex(theVariables,static_cast<Variable*>(sortvar))>=0,"cannot register sort variable that is not in theVariables");
  for (auto sv : theSortVariables)
    if (sortvar==sv)return;
  theSortVariables.push_back(sortvar);
  theSortDirections.push_back(dir);
  uassert(theSortVariables.size()==theSortDirections.size(),"rsv size");
}

SortDirection Environment::getSortDirection(SortVariable*sortvar){
  int n=(int) theSortVariables.size();
  uassert(n==(int)(theSortDirections.size()), "egsd size");
  for(int i=0;i<n;++i)
    if (theSortVariables[i]==sortvar)
      return theSortDirections[i];
  uassert(false,"getSortDirection: No such variable: ", sortvar->name);
  return SortDirection::None;
}

bool Environment::isQuietSortVariable(SortVariable*nv)const{
  if (myindex(theSortVariables,nv)<0)
    uassert(false, "isQuietSortVariable: expected a sort variable");
  return myindex(theQuietSortVariables,nv)>=0;
}

void Environment::setQuietSortVariable(SortVariable*nv){
  if(myindex(theSortVariables,nv)<0)
    uassert(false, "setQuietSortVariable: not a sort variable");
  if (isQuietSortVariable(nv))
    uassert(false, "setQuietSortVariable: variable already quiet");
  theQuietSortVariables.push_back(nv);
}

bool Environment::isQuietPersistentVariable(Variable*v)const{
  return myindex(theQuietPersistentVariables,v)>=0;
}

void Environment::setQuietPersistentVariable(Variable*v){
  if(myindex(theQuietPersistentVariables,v)>=0)
    uassert(false, "setQuietPersistentVariable: already set to be quiet", v->name);
  theQuietPersistentVariables.push_back(v);
}

void Environment::reset(){
  for(Variable* v :theVariables){
    uassert(v,"environment reset null");
    if(!v->isPersistent())v->reset();
  }
}

vector<Variable*>Environment::getPersistentVariables(){
  vector<Variable*>ret;
  for (auto v: theVariables){
    uassert(v,"egpv");
    if (v->isPersistent())
      ret.push_back(v);
  }
  return ret;
}

void Environment::registerAtomicVariable(Variable*v){
  uassert(Atomic::isAtomizable(v),"registerAV: invalid variable");
  if(std::count(theAtomicVariables.begin(),theAtomicVariables.end(),v)<=0)
    theAtomicVariables.push_back(v);
  uassert(std::count(theAtomicVariables.begin(),theAtomicVariables.end(),v)==1,"rAV eh?");
}

