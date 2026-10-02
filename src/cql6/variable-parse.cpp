#include "node.h"
#include "variable.h"
#include "numericvariable.h"
#include "pieceidvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "tokens.h"
#include "environment.h"
SquareVariable*Tokens::match_squarevariable(){
  string name=match_id();
  if(name.empty())return NULL;
  Variable*v=environment->find(name);
  if(!v) return environment->createSquareVariable(name);
  auto sv=dynamic_cast<SquareVariable*>(v);
  uassert(sv,"Square variable expected, got a non-square variable: ",name);
  return sv;
}

PieceIdVariable*Tokens::match_pieceidvariable(){
  string name=match_id();
  if(name.empty())return NULL;
  Variable*v=environment->find(name);
  if(!v) return environment->createPieceIdVariable(name);
  auto tv=dynamic_cast<PieceIdVariable*>(v);
  uassert(tv,"Piece variable expected, got a non-piece variable: ",name);
  return tv;
}


  
PositionVariable*Tokens::match_positionvariable(){
  string name=match_id();
  if(name.empty())return NULL;
  if(0)printf("match_positionvariable: matching, got name of: %s\n",name.c_str());
  Variable*v=environment->find(name);
  if(0){printf("match_positionvariable: got position variable of: %p\n",v);}
  if(!v) return environment->createPositionVariable(name);
  auto pv=dynamic_cast<PositionVariable*>(v);
  uassert(pv,"Position variable expected, got a non-square variable: ",name);
  if(0)printf("match_positionvariable: got new non-null position variable of: %s\n",pv->name.c_str());
  return pv;
}

TransformVariable*Tokens::match_transformvariable(){
  string name=match_id();
  if(name.empty())return NULL;
  if(0)printf("match_transformvariable: matching, got name of: %s\n",name.c_str());
  Variable*v=environment->find(name);
  if(0){printf("match_transformvariable: got transform variable of: %p\n",v);}
  if(!v) return environment->createTransformVariable(name);
  auto tv=dynamic_cast<TransformVariable*>(v);
  uassert(tv,"Transform variable expected, got a non-transform variable: ",name);
  if(0)printf("match_transformvariable: got new non-null transform variable of: %s\n",tv->name.c_str());
  return tv;
}

TransformVariable*Tokens::match_existingtransformvariable(){
  int x=save();
  TransformVariable * tv{NULL};
  Variable*v{NULL};
  string name=match_id();
  if(name.empty()) goto nullret;
  v=environment->find(name);
  if(!v) goto nullret;
  tv=dynamic_cast<TransformVariable*>(v);
  if(tv) return tv;
 nullret:
  restore(x);
  return NULL;
}

NumericVariable*Tokens::match_numericvariable(){
  string name=match_id();
  if(name.empty())return NULL;
  Variable*v=environment->find(name);
  if(!v) return environment->createNumericVariable(name);
  auto nv=dynamic_cast<NumericVariable*>(v);
  uassert(nv,"Numeric variable expected, got a non-numeric variable: ",name);
  return nv;
}

NumericVariable*Tokens::match_existingnumericvariable(){
  int x=save();
  Variable*v{NULL};
  NumericVariable*nv{NULL};
  string name=match_id();
  if(name.empty()) goto nullret;
  v=environment->find(name);
  if(!v||!v->isNumeric()) goto nullret;
  nv=v->asNumeric();
  uassert(nv,"menv internal");
  return nv;
 nullret:
  restore(x);
  return NULL;
}

StringVariable*Tokens::match_stringvariable(){
  string name=match_id();
  if(name.empty())return NULL;
  Variable*v=environment->find(name);
  if(!v) return environment->createStringVariable(name);
  auto nv=dynamic_cast<StringVariable*>(v);
  uassert(nv,"Numeric variable expected, got a non-numeric variable: ",name);
  return nv;
}

StringVariable*Tokens::match_existingstringvariable(){
  int x=save();
  StringVariable*sv{NULL};
  Variable*v{NULL};
  string name=match_id();
  if(name.empty()) goto nullret;
  v=environment->find(name);
  if(!v||!v->isString()) goto nullret;
  sv=v->asString();
  uassert(sv,"mesv internal");
  return sv;
 nullret:
  restore(x);
  return NULL;
}


  
