#include "raynode.h"
bool RayNode::isSet()const{
  return theRange==NULL;
}

bool RayNode::isNumeric()const{
  return theRange!=NULL;
}


RayNode::RayNode(vector<Direction>dirs,
		 vector<SetBase*> sets,
		 bool isattack,
		 Range*r,
		 bool returnfirst){
  uassert(dirs.size()>0,"raynode arg");
  uassert(sets.size()>=2,"raynode arg2");
  directions=dirs;
  std::stable_sort(directions.begin(), directions.end());
  for(auto s:sets) uassert(s,"rnrn s");
  designators=sets;
  for (int i=0;i<designators.size();++i)
    designatorMasks.push_back(SquareMask());
  uassert(designatorMasks.size()==designators.size(),"rnrn dmds");
  isAttack=isattack;
  if(isAttack) uassert(dirs.size()==Direction::allDirections().size(),"raynode constructor internal");
  theRange=r;
  theReturnFirst=returnfirst;
}

void RayNode::compute(QPos*qpos){
  const pieceT * board=qpos->getBoard();
  SquareMask occupied;
  for(squareT s=0;s<64;++s) if(board[s]!=EMPTY)occupied.insert(s);
  destMask.clear();
  fromMask.clear();
  count=0;
  uassert(designators.size()>1,"rn mp s");
  uassert(designatorMasks.size()==designators.size(),"rn mp ds2");
  for (int i=0;i<designators.size();++i){
    SetBase*designator=designators.at(i);
    uassert(designator,"rn mp ds3");
    designatorMasks[i]=designator->getSquares(qpos);
  }
  SquareMask startmask=designatorMasks[0];
  SquareMask thisdest;
  for (squareT sq=0;sq<64;++sq)
    if(startmask.member(sq))
      for (Direction direction:directions){
	if (isAttack&&
	    !direction.isCompatible(board[sq]))
	  continue;
	thisdest=match_starting(sq,1,designatorMasks,direction,occupied);
	if(thisdest.nonempty()){
	  count++;
	  destMask|=thisdest;
	  fromMask.insert(sq);
	}
      } //for each direction
}

bool RayNode::match_position(QPos*qpos){
  if(isSet())
    return getSquares(qpos).nonempty();
  else if (isNumeric()){
    NumValue v{-1};
    return match_count(qpos,&v);
  }
  uassert(false,"raynode mp fall through");
  return false;
}

bool RayNode::match_count(QPos*qpos, NumValue*value){
  eassert(theRange,"No range: must include a range when counting rays");
  compute(qpos);
  if(theRange->valid(count)){
    *value=(NumValue)(count);
    return true;
  }
  return false;
}

/*This takes a square, an index into a vector of masks (the ray filters) , a direction, and
the occupied mask. The square is the PREVIOUS square on the ray in question which is
supposed to be compatible with the masks. Because it is the previous square, 
the maskindex must be >0*/

SquareMask RayNode::match_starting(const squareT square, 
				   const int maskindex,
				   const vector<SquareMask> &masks,
				   const Direction direction,
				   const SquareMask occupied){
  SquareMask ret;
  if(!square_valid(square))return ret;
  int ndesignators=(int)(masks.size());
  uassert(ndesignators>1,"internal match_starting");
  uassert(maskindex>0&&maskindex<ndesignators,"raynode match_starting maskindex");
  squareT currentsquare=square; //the previous square being analyzed
  int currentindex=maskindex; // the current index
  //At the start of this loop, currentsquare should be the previous square
  while(true){
    uassert(currentindex<ndesignators&&currentindex>0,"loop match_starting cind");
    uassert(square_valid(currentsquare),"match_starting svcs");
    // Now currentsquare is the square being examined
    currentsquare=direction.apply(currentsquare);
    if(!square_valid(currentsquare))return ret;
    bool islast=(currentindex==ndesignators-1);
    bool inmask=masks[currentindex].member(currentsquare);
    bool isempty=!occupied.member(currentsquare);
    //8 cases here depending on these bools
    if (islast&&inmask&&isempty) //case 1
      ret.insert(currentsquare);
    else if (islast&&inmask&&!isempty){ // case 2
      ret.insert(currentsquare);
      return ret;
    }
    else if (islast&&!inmask&&isempty) // case 3
      ;
    else if(islast&&!inmask&&!isempty) //case 4
      return ret;
    else if (!islast&&inmask&&isempty){ // case 5
      /*this is the tricky case. An internal ray mask is empty. We first treat it as if that
        mask was matched, by calling the function again with the next index. Note that because
	maskindex will be >0, the currentsquare will always be the previous square in the ray
        then we do the case where that mask was not matched (implicitly
        by letting the loop run without incrementing maskindex*/
      /*The released 9.186 had a bug in the below. Fixing in 9.188 (maskindex to currentindex)*/
      ret |= match_starting(currentsquare,currentindex+1,masks,direction,occupied);
    }
    else if (!islast&&inmask&&!isempty) //case 6
      ++currentindex;
    else if (!islast&&!inmask&&isempty)//case 7
      ;
    else if (!islast&&!inmask&&!isempty)//case 8
      return ret;
    else
      uassert(false,"match_starting_fall_through");
  }
  uassert(false,"match_starting internal loop");
  return ret;
}

SquareMask RayNode::getSquares(QPos*qpos){
  uassert(isSet(),
	  "A ray can only be used as a set filter when it does not have a range");
  compute(qpos);
  if(theReturnFirst)
    return fromMask;
  return destMask;
}
  
void RayNode::deepify(){
  clonevec(designators);
}

vnode RayNode::children()const{
  vnode ret;
  for (Node* node:designators){
    uassert(node,"raynode: children: null designator");
    myinsert(ret,node);
  }
  return ret;
}

RayNode* RayNode::makeFromAttackArrow(vector<SetBase*>constituents,
				      AttackArrowDirection dir){
  uassert(constituents.size()>2,"mfraa expected bigger args");
  uassert(AttackArrowDirectionIsValid(dir),"mfraa bad arrow");
  bool isright=AttackArrowDirectionIsRight(dir);
  bool isleft=AttackArrowDirectionIsLeft(dir);
  uassert(isright+isleft==1,"mfaa arrow");
  if(isleft)std::reverse(constituents.begin(),constituents.end());
  for(auto constituent:constituents)
    uassert(constituent,"unexpected null in arg args in mfraa");
  return new RayNode(Direction::allDirections(),
		     constituents,
		     true, //is attack
		     NULL, // range
		     isright //return as a set the first argument
		     );
}

  
