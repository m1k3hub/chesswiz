#include "hhdbawardnode.h"
#include "hhdbkeyword.h"
#include "util.h"
HhdbAwardNode::HhdbAwardNode(const string& keytype, bool restrictspecial, bool usemax) :
  awardType{keytype},
  restrictSpecial{restrictspecial},
  useMax{usemax}
{
  uassert (HhdbKeyword::isAwardTypeKey(awardType), "hhdbawardnode args: ", awardType);
  if (awardType=="prize")restrictPrize=true;
  else if (awardType=="hm")restrictHm=true;
  else if (awardType=="commendation")restrictCommendation=true;
  else if (awardType=="award");
  else uassert(false,"HhdbAwardNode: switch");
}

bool HhdbAwardNode::match_count(QPos*qpos, NumValue*value){
  int ret{-1};
  if (!compute(qpos,&ret)) return false;
  if (ret>0) {*value=ret; return true;}
  return false;
}


bool HhdbAwardNode::match_position(QPos*qpos){
  int ignore=0;
  return compute(qpos,&ignore);
}
  
/* Get the white player field. look for a start of the form in the bnf.
   set the passed retp to the relevant rank, unless it is a special rank and
   special is not explicitly restricted to, in which case set it to 0. 
   If the rank is absent return the relevant rank in *retp;
*/

bool HhdbAwardNode::compute(QPos*qpos, int * retp ){
  const string srcs=QMarkBoard::getEvent(qpos->qgame); //what to read
  int r1=0; //the first rank if it exists
  int r2=0; //the second rank if it exists
  bool hasranks; //there are ranks;
  bool hasspecial=false; //game is special prize. spell it out for clarity
  bool hashm=false; //seen 'hm'
  bool hascommendation=false; //seen 'c'
  bool hasprize=false; //seen 'p'
  string curr=srcs; //unparsed portion of string, very inefficient
  if (! readRanks(&curr, &r1,&r2)) return false;
  if (r1==0){
    uassert (r2==0, "hhdbawardnode ranks");
    hasranks=false;}
  else {hasranks=true;
    uassert (r1>0 && r2>=r1, "hhdbawardnode ranks?");}
  if (!hasranks && util::readString(&curr,"sp") ||
      hasranks && util::readString(&curr,".sp"))
    hasspecial=true;
  if (util::readString(&curr,".p"))
    hasprize=true;
  else if (util::readString(&curr,".hm"))
    hashm=true;
  else if (util::readString(&curr,".c"))
    hascommendation=true;
  else return false;
  //We've done the parsing, now for the matching
  if (restrictPrize&&!hasprize ||
      restrictCommendation && !hascommendation ||
      restrictHm && !hashm) return false;
  if (restrictSpecial&&!hasspecial) return false;
  if (!hasranks){
    r1=1;
    r2=genericPlaceMax;}
  if (hasspecial && !restrictSpecial){ //ignore ranks in this case
    *retp=0;
    return true;}
  *retp = useMax ? r2 : r1;
  return true;
}

/* read ranks of the form rank | rank/rank. 
If no ranks are read r1p and r2p are
set to 0. If parse error occurs then the *srcp is still destroyed. Otherwise set
to point to first unread character*/

bool HhdbAwardNode::readRanks(string*srcp, int * r1p, int * r2p){
  *r1p=0;
  *r2p=0;
  if (!util::readPositiveInt(srcp,r1p)) return true; //valid but no ranks
  if (!util::readString(srcp,"/")){
    *r2p=*r1p;
    return true;
  }
  if (!util::readPositiveInt(srcp,r2p)) return false; //malformed
  if (*r2p<= *r1p) return false;
  return true;
}

