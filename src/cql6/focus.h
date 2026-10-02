#pragma once
#include<array>
#include "node.h"
#include "capturetype.h"
#include "focuscapturenode.h"

//see the class path-focus.cpp for implementation
class PathCon;
class SetBase;
class Focus:public NeverMatch{
 public:
  Focus(SetBase*,CaptureType);
  SetBase*theSetBase{NULL};
  SetBase*getSetBase()const{return theSetBase;}
  CaptureType theCaptureType{CaptureType::None};
  CaptureType getCaptureType()const{return theCaptureType;}
  std::array<bool,32> markMask; //warning: initially invalid
  bool isValid()const{return markMaskValid;}
  bool markMaskValid{false};
  void clear();
  void initialize(QPos*qpos);
  bool isCapture()const{return theCaptureType==CaptureType::Capture;}
  bool isNonCapture()const{return theCaptureType==CaptureType::NonCapture;}
[[nodiscard]]  Focus*clone()override;
  vnode children()const override;
  void deepify()override;
  void print()override;
  string thisclass()const override{return "Focus";}
  vector<QMove*>getFocusedMoves(const QPos* root)const;
  vector<QMove*>getFocusedChildMoves(const QPos* root)const;
  bool inFocus(const QPos*)const;
  bool inFocus(const QMove*)const;
  bool markFocused(markT)const;
};
