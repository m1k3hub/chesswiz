#pragma once
#include "node.h"
#include "seqdir.h"
#include "seqconstituent.h"

class SequenceBase : public Node{ // abstract
 public:
  void clear();
  bool isNumeric()const override;
  bool isSequence()override{return true;}
  bool isPosition()const override;
  virtual bool isFuture()=0;
  virtual bool isPast()=0;
  bool match_position(QPos*qpos)override;
  bool isSkip()const;
  colorT getSkipColor()const;
  bool skipColor(colorT)const;
  bool skipCurrentPosition(QPos*qpos)const;
  void clearSkipColor();
  void setSkipColor(colorT);
  void initializeSkip(QPos*);
  void exitMatch();
  virtual SeqDir getSearchDirection()=0;
  void notate(QPos*start,QPos*finish);
  bool canModifyCurpos()const override{return true;}  
  void computeSkip(QPos*qpos);
  HolderConstituent* getSkipConstituent()const;
  virtual void compute (QPos*qpos);
  virtual void compute(VectorConstituent*,QPos*qpos);
  virtual void compute(StarConstituent*,QPos*qpos);
  virtual void compute(RepeatConstituent*,QPos*qpos);
  virtual void compute(HolderConstituent*,QPos*)=0;
  virtual void compute(PlusConstituent*,QPos*qpos);
  virtual void compute(OptionalConstituent*,QPos*qpos);
  virtual void compute(RepeatInProcessConstituent*,QPos*);
  virtual bool computeNull();
  bool match_count(QPos*qpos,NumValue*value)override;
  bool match_positionvalue(QPos*,QPos**)override;
  vector<SeqConstituent*> constituents;
  void print()override;
  Range*range{NULL};
  int count{-1};
  bool firstMatch{false};
  bool isPrimary{false};
  bool isSecondary{false};
  bool returnFinish{false};
  bool isQuiet{false};
  void deepify()override;
  SequenceBase(vector<SeqConstituent*> scs,Range*r, bool isskip,bool nestban,bool firstmatch,bool isprimary, bool issecondary, bool returnfinish, bool isquiet);
  vnode children()const override;
  int nconstituents()const;
  bool valid_constituent (int offset)const;
  QPos*theQpos{NULL};
  SeqConstituent* getConstituent (int offset)const;
  vector<SeqConstituent*>theStack;
 private:
  HolderConstituent* theWhiteHolder{NULL};
  HolderConstituent* theBlackHolder{NULL};
  colorT theSkipColor{NOCOLOR};

  //nest members
 public:
  bool nestBan{false}; //whether this bans nesting
  void nestRegisterPosition(QPos*qpos); //register current position as having matched
  void nestRegisterPositions(QPos*start,QPos*finish);
  bool nestSeenPosition(QPos*qpos); // query if this filter has seen current position
  void nestClearPositions(); //clear all positions that have been seen by this
  std::set<QPos*> nestIds; // the positions that have been matched by part of the current filter

  ////SeqRet members
 public:
  QPos*bestSoFar{NULL};
  bool isTrue();
  bool isFalse();
  ///commentStack
 private: 
    CommentStack commentStack; // entries from the main stack effectiveBottom to effectiveTop and then the reversed entries here are the best stack
  CommentStack*mainStack{NULL}; // the main stack
  int effectiveBottom{-1}; // the top of the main stack when the seqret was initialized. The main stack should never go below this value
  int effectiveTop{-1}; //Entries in the main stack from effectiveBottom exclusive to effectiveTop exclusive are stored in the main stack but actually
                        //belong to this seqret. Whenever they are popped, they should be transferred to the local commentStack.
  int trueSize{-1};
 public:
  void initializeComments(QPos*);
  void swapComments(QPos*);
  void commentStacksValid();
  int markComments(); //we actually don't need this here, but since we have restoreComments we use it
  void restoreComments(int);
  void pushComments(); //push all comments out to the main stack, deleting everything else on stack since effectiveBottom
  void mergeSuccess(QPos*);
  void popComment();

 public:
  SeqStack seqStack;
};



