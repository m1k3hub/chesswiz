#pragma once
#include "node.h"
#include "focustype.h"
#include "pathcon.h"
#include "pathstatus.h" //the PathStatus class, not the same as path-status.h
#include "focus.h"
#include "atomic.h"
#include "piecepathnode.h"

class PathNode:public Node{
public:
  /*overridden methods and constructor*/
  PathNode(vector<PathCon*> lcs,
	   Range*r,
	   Focus*focus,
	   bool nestban,
	   bool firstmatch,
	   bool isprimary,
	   bool returnfinish,
	   Node*max,
	   const vector<Variable*>&atomicvariables,
	   bool usepiecepath,
	   bool isquiet,
	   string title,
	   bool isverbose,
	   bool keepallbest);
  void deepify()override;
  vnode children()const override;
  void print()override;
  bool isPathNode()const override {return true;}
  PathNode*asPathNode()override{return this;}
  bool match_position(QPos*)override;
  bool match_count(QPos*qpos,NumValue*value)override;
  bool match_positionvalue(QPos*,QPos**)override;
[[nodiscard]]  PathNode*clone()override;
  void mergeSuccess();
  string thisclass()const override{return "PathNode";}
  PathStatus createPathStatus() const;
  void clear();
  void exitMatch();
  void notate(QPos*start,QPos*finish);
  void compute(); //just given a stack and a current position
  void computeChainCon(ChainCon*);
  void computeStarCon(StarCon*);
  void computeHolderCon(HolderCon*);
  void computeDashConUnfocused(DashCon*);
  void computeDashConFocused(DashCon*);
  void computePlusCon(PlusCon*);
  void computeOptionalCon(OptionalCon*);
  void computeRepeatCon(RepeatCon*);
  void computeRepeatInProcessCon(RepeatInProcessCon*);
  bool canModifyCurpos()const override{return true;}
  
#include "path-static.h" //static/parser options
#include "path-status.h" //dynamic status
#include "path-comment.h" //smart comments/comment stack
#include "path-nest.h" // nestban related stuff
#include "path-atomic.h" // atomic variable related stuff
};  

