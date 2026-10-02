#pragma once
class SeqConstituent;
class SeqRet;
typedef vector<SeqConstituent*>SeqStack;
class SeqConstituent : public NeverMatch{
public:
  virtual void print()=0;
[[nodiscard]]  virtual SeqConstituent* clone()=0;
  virtual bool matchesNull()=0;
  virtual void compute(SequenceBase*base,QPos*qpos)=0;
};
#ifndef CVV
#define CVV(name) string thisclass()const{return #name;} [[nodiscard]]name* clone()
#endif

class RepeatConstituent : public SeqConstituent{
public:
  SeqConstituent* constituent{NULL};
  RepeatConstituent(SeqConstituent*,int, int);
  CVV(RepeatConstituent);
  int min= -1;
  int max= -1;
  bool matchesNull();
  void print();
  vnode children()const{return vnode{constituent};}
  void deepify(){constituent=constituent->clone();}
  void compute(SequenceBase*base,QPos*qpos);
};

class StarConstituent : public SeqConstituent{
public:
  SeqConstituent*constituent{NULL};
  //  StarConstituent(vector<SeqConstituent*>);
  StarConstituent(SeqConstituent*);
  CVV(StarConstituent);
  bool matchesNull();
  void print();
  vnode children()const{return vnode{constituent};}
  void deepify(){constituent=constituent->clone();}
  void compute(SequenceBase*base,QPos*qpos);
};

class HolderConstituent : public SeqConstituent{
public:
  HolderConstituent(Node*);
  Node*filter{NULL};
  CVV(HolderConstituent);
  void print();
  vnode children()const{return vnode{filter};}
  void deepify(){filter=filter->clone();}
  bool matchesNull();
  void compute(SequenceBase*base,QPos*qpos);
};

class VectorConstituent : public SeqConstituent{
public:
  vector<SeqConstituent*>constituents;
  VectorConstituent(vector<SeqConstituent*>& cs, SeqDir);
  SeqDir direction{SeqDir::None};
  void print();
  CVV(VectorConstituent);
  vnode children()const;
  void deepify(){clonevec(constituents);}
  bool matchesNull();
  void compute(SequenceBase*base,QPos*qpos);
};

class PlusConstituent : public SeqConstituent{
public:
  StarConstituent* getStarConstituent(){return theStarConstituent;}
  SeqConstituent* getConstituent();
  PlusConstituent(SeqConstituent*c);
  CVV(PlusConstituent);
  vnode children()const{return vnode{theStarConstituent};}
  void deepify(){theStarConstituent=theStarConstituent->clone();}
  bool matchesNull();
  void print();
  void compute(SequenceBase*base,QPos*qpos);
private:
  StarConstituent* theStarConstituent{NULL};
};

class OptionalConstituent : public SeqConstituent{
public:
  OptionalConstituent(SeqConstituent*);
  SeqConstituent*constituent{NULL};
  CVV(OptionalConstituent);
  void print();
  vnode children()const{return vnode{constituent};}
  void deepify(){constituent=constituent->clone();}
  bool matchesNull();
  void compute(SequenceBase*base,QPos*qpos);
};

class RepeatInProcessConstituent : public SeqConstituent{
public:
  RepeatInProcessConstituent(RepeatConstituent*);
  RepeatConstituent* theRepeatConstituent{NULL};
  int nSeen{0};
  int min();
  int max();
  SeqConstituent* getConstituent();
  void compute(SequenceBase*,QPos*);
  string thisclass()const{return "RepeatInProcessConstituent";}
[[nodiscard]]  RepeatInProcessConstituent*clone();
  void print();
  void deepify();
  vnode children()const;
  bool matchesNull();
};

#ifdef CVV
#undef CVV
#endif
