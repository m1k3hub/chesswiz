#pragma once
#include "node.h"
enum HhdbAwardType {HhdbAward,HhdbSpecialAward, HhdbSpecialPrize, HhdbSpecialHm, HhdbSpecialCommendation, HhdbPrize, HhdbHm, HhdbCommendation};
class HhdbAwardNode : public Node{
 public:
  HhdbAwardNode(const string& awardtype, bool  restrictspecial, bool usemax);
  const string awardType;
  bool restrictSpecial{false}; //only allow special awards; return ranks in that case
  bool restrictPrize{false}; // only allow prizes
  bool restrictCommendation{false}; // only allow commendations
  bool restrictHm{false}; // only allow hms
  const bool useMax{false}; // use the max rank instead of the default minrank
  bool match_count(QPos*qpos, NumValue*value);
  bool match_position(QPos*qpos);
  bool isNumeric()const{return true;}
  string thisclass()const{return "HhdbAwardNode";}
[[nodiscard]]  HhdbAwardNode*clone();
  vnode children()const{return  vnode{};};
  void deepify(){};
  void print();
  static const int genericPlaceMax=10000; // top rank value used for missing rank
 private:
  bool compute(QPos*qpos, int * val);
  bool readRanks(string*srcp, int*r1p, int*r2p);
};
  
    
