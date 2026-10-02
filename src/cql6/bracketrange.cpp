#include "bracketrange.h"
#include <algorithm>
using std::max;
using std::min;

/* A BracketRange object corresponds to a substring index expression of the form:
      [left] or
      [left? : right?]
  In the former case, the singleIndex member is set to true.
  Use getBounds() to actually get the appropriate bounds
*/

BracketRange::BracketRange(Node*l,Node*r,bool singleindex):theLeft(l),theRight(r),singleIndex(singleindex){
  uassert (theLeft !=NULL && theLeft->isNumeric(), "br missing or bad left");
  uassert (theRight==NULL || theRight->isNumeric(), "br bad right");
  if(singleIndex)uassert(theRight==NULL,"bracketrange singleindex");
}

/*  getBounds()
     set leftbound and rightbound to the bound values for a target string
    of length len. That is, if this was created with 
    bounds of filters x and y, and if target is a string
    of length len, then
      target[x:y]
    should be equivalent to
      target[leftbound:rightbound]
    after execution (if true is returned).

    A missing : is NOT the same as leftbound:leftbound+1.
    If a : is missing, (if singleIndex is true) then
    an out-of-bound index is FALSE. But for a range, the
    range is massaged to always get a range.

   If singleIndex is true (no :) then rightbound is set to leftbound+1
   but should really never be used.

   returns: true if target[x:y] or target[x] would match
*/

bool BracketRange::getBounds(QPos*qpos, //current position
			     int len,   // length of the target string
			     NumValue*leftbound, //where left bound is stored (int)
			     NumValue*rightbound)//where right bound is stored
{
  uassert(leftbound&&rightbound, "getBounds pointers");
  NumValue nl=0, nr=0;
  if (!theLeft->match_count(qpos,&nl))
    return false;
  int l=(int)nl;
  if (l<0) l+=len;
  if (singleIndex){
    if (l<0||l>=len)return false;
    *leftbound = (NumValue)l;
    *rightbound = (NumValue) (l+1);
    return true;
  }
  uassert(!singleIndex,"getBounds internal");
  if (theRight && !theRight->match_count(qpos,&nr))
    return false;
  int r=(int)nr;
  if (theRight==NULL)r=len;
  l=max(l,0);
  l=min(l,len);
  if (r<0) r+=len;
  r=max(r,l);
  r=min(r,len);
  *leftbound=(NumValue)l;
  *rightbound=(NumValue)r;
  return true;
}


void BracketRange::deepify(){
  theLeft=theLeft->clone();
  if (theRight)
    theRight=theRight->clone();
}

bool BracketRange::match_position(QPos*qpos){
  uassert(false, "match_position was called on BracketRange. Internal error.");
  return false;
}

vnode BracketRange::children()const{
  vnode ret{theLeft};
  if(theRight!=theLeft && theRight!=NULL)
    ret.push_back(theRight);
  return ret;
}
  
    
