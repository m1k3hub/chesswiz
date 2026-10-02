#pragma once
#include "node.h"
#include "dashnode.h"
#include "focus.h"

class QCon;
class PathRet;
class PathCon;
class StarCon;
class OptionalCon;
class PlusCon;
class ChainCon;
class RepeatCon;
class RepeatInProcessCon;
class HolderCon;
class DashCon;
class DashNode;

typedef vector<PathCon*>PathConStack;
class PathCon : public NeverMatch{
public:
  void print()override=0;
[[nodiscard]]  PathCon* clone()override=0;
  //  virtual bool matchesNull()=0;
  virtual bool hasDash() const=0;
  bool isPathCon()const override{return true;}
  PathCon* asPathCon()override{return this;}
  bool theIsInitial{false}; //true if this is the first constituent of the dash
  virtual bool isInitial() const{return theIsInitial;}
  virtual void setIsInitial(){theIsInitial=true;} //overridden in ChainCon to be recursive
  bool canModifyCurpos()const override{return true;}

  /*conversions*/
  virtual bool isStarCon()const{return false;}
  virtual StarCon* asStarCon(){return NULL;}
  virtual bool isChainCon()const{return false;}
  virtual ChainCon* asChainCon(){return NULL;}
  virtual bool isHolderCon()const{return false;}
  virtual HolderCon* asHolderCon(){return NULL;}
  virtual bool isDashCon()const{return false;}
  virtual DashCon* asDashCon(){return NULL;}
  virtual bool isPlusCon()const{return false;}
  virtual PlusCon* asPlusCon(){return NULL;}
  virtual bool isRepeatCon()const{return false;}
  virtual RepeatCon* asRepeatCon(){return NULL;}
  virtual bool isRepeatInProcessCon()const{return false;}
  virtual RepeatInProcessCon* asRepeatInProcessCon(){return NULL;}
  virtual bool isOptionalCon()const{return false;}
  virtual OptionalCon* asOptionalCon(){return NULL;}
  virtual bool isWildcard()const{return false;}
};
  
  /*Subclasses: (in name-of-class.h and .cpp)
    dashcon.h
    dashfocuscon.h
    chaincon.h
    holdercon.h
    optionalcon.h
    pluscon.h
    repeatcon.h
    repeatinprocesscon.h
    starcon.h
  */      
