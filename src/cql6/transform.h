#pragma once
#ifdef CQL6_EMBEDDED
#include "scidb_retain.h"
#endif
class Transform {
 public:
#ifdef CQL6_EMBEDDED // scidb: search ownership
  SCIDB_SEARCH_ALLOCATOR(Transform)
  virtual ~Transform() = default;
#endif
  virtual squareT transform(squareT s)const=0;
  virtual bool flipsSquareParity()const{return false;}
  static vector<Transform*>nonidentity(const vector<Transform*>&);
  virtual void print()const;
  virtual Direction transform(Direction)const=0;
  virtual SquareMask transform(SquareMask)const=0;
  virtual string thisclass()const=0;
  virtual Node* transform(Node* n);
  virtual colorT transformColor(colorT color)const;
  virtual pieceT transformPiece(pieceT piece)const;
  DirectionParameter transform(DirectionParameter)const;
  virtual bool flipsColor()const{return false;}
  Transform* transform(const Transform*)const;
  Transform* compose(Transform*);
  virtual bool isIdentity()const=0;
  virtual string toString()const=0;
};

class PiOver4Transform:public Transform{
 public:
  string thisclass()const override{return "PiOver4Transform";}
  int times{-1};
  virtual bool flipsSquareParity()const override;
  squareT transform(squareT)const override;
  Direction transform(Direction)const override;
  PiOver4Transform(int t);
  Direction rotate45(Direction)const;
  static vector<Transform*>rotations();
  SquareMask transform(SquareMask m)const override;
  void print() const override;
  bool isIdentity()const override;
  string toString()const override;
};

class DihedralTransform : public Transform{
 public:
  string thisclass()const override{return "DihedralTransform";}
  bool reflectx{false};
  bool reflecty{false};
  bool swap{false};
  virtual bool flipsSquareParity()const override;
  squareT transform(squareT)const override;
  Direction transform(Direction)const override;
  DihedralTransform(bool rx, bool ry, bool swap);
  static DihedralTransform* flipVertical();
  static DihedralTransform* flipHorizontal();
  static vector<Transform*> rotations();
  SquareMask transform(SquareMask m)const override;
  void print()const override;
  bool isIdentity()const override;
  static vector<Transform*> allDihedral();
  //  DihedralTransform* reflect(Direction);
  string toString()const override;
};

class ShiftTransform : public Transform{
 public:
  string thisclass()const override{return "ShiftTransform";}
  int xoffset{0};
  int yoffset{0};
  virtual bool flipsSquareParity()const override;
  squareT transform(squareT)const override;
  Direction transform(Direction d)const override{return d;}
  ShiftTransform(int xoff, int yoff);
  virtual void print()const override;
  SquareMask transform(SquareMask)const override;
  static vector<Transform*>allShift();
  static vector<Transform*>shiftHorizontal();
  static vector<Transform*>shiftVertical();
  bool isIdentity()const override;
  string toString()const override;
};

class ColorTransform : public Transform{
 public:
  virtual bool flipsSquareParity()const override{return false;}
  squareT transform(squareT s)const override{return s;}
  Direction transform(Direction d)const override {return d;}
  SquareMask transform(SquareMask m)const override{return m;}
  string thisclass()const override{return "ColorTransform";}
  bool flipsColor()const override{return true;}
  static Transform* flipColorTransform();
  bool isIdentity()const override;
  string toString()const override;
};
  
class IdentityTransform : public Transform{
 public:
  virtual bool flipsSquareParity()const override{return false;}
  squareT transform(squareT s)const override{return s;}
  Direction transform(Direction d)const override{return d;}
  SquareMask transform(SquareMask m)const override{return m;}
  string thisclass()const override{return "IdentityTransform";}
  string toString()const override{return "";}
  bool isIdentity()const override{return true;}
};

class ComposeTransform: public Transform{
 public:
  vector<const Transform*> transforms;
  squareT transform(squareT)const override;
  virtual bool flipsSquareParity()const override;
  Direction transform(Direction)const override;
  void print()const override;
  ComposeTransform(vector<const Transform*>);
  ComposeTransform(const Transform* t, const Transform*s);
  static vector<Transform*> composeVectors(vector<const Transform*>, vector<const Transform*>);
  static vector<Transform*> composeVectors(vector<Transform*>, vector<Transform*>);
  string thisclass()const override{return "ComposeTransform";}
  SquareMask transform(SquareMask)const override;
  bool flipsColor()const override;
  string toString() const override;
  bool isIdentity()const override;
};



  
