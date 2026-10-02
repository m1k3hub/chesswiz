#include "makesquarenode.h"
MakeSquareNode::MakeSquareNode(Node* file, Node* rank):theFile(file),theRank(rank){
  uassert(theRank&&theFile&&theRank->isNumeric()&&theFile->isNumeric(),"MakeSquareNode args");
}

MakeSquareNode::MakeSquareNode(Node*name):theName(name){
  uassert (name&&name->isString(),"msn bad name arg");
}

vnode MakeSquareNode::children()const{
  vnode ret;
  if (theFile) ret.push_back(theFile);
  if (theRank&&theRank!=theFile)
    ret.push_back(theRank);
  if (theName) ret.push_back(theName);
  uassert (((theFile==NULL&&theRank==NULL)
	    + (theName==NULL))==1,"makesquare children args");
  return ret;
}

SquareMask MakeSquareNode::getSquaresString(QPos*qpos){
  string val;
  SquareMask ret;
  if (!theName->match_stringvalue(qpos,&val))
    return ret;
  if (val.size()!=2) return ret;
  char filec=val[0];
  char rankc=val[1];
  if (filec<'a'||filec>'h'||rankc<'1'||rankc>'8')return ret;
  squareT s = square_Make(filec-'a', rankc-'1');
  ret.insert(s);
  return ret;
}

SquareMask MakeSquareNode::getSquares(QPos*qpos){
  if (theName==NULL){
    uassert(theFile!=NULL && theRank!=NULL,"msn gss fr");
    return getSquaresNumeric(qpos);
  }
  uassert(theFile==NULL&&theRank==NULL,"msn gss fr 2");
  return getSquaresString(qpos);
}

SquareMask MakeSquareNode::getSquaresNumeric(QPos*qpos){
  SquareMask ret;
  NumValue rank{-1};
  NumValue file{-1};
  if (theFile->match_count(qpos,&file)&&
      theRank->match_count(qpos,&rank)&&
      rank>=1&&rank<=8&&
      file>=1&&file<=8){
      squareT s=square_Make(file-1,rank-1);
      uassert(square_valid(s),"msn getSquares square");
      ret.insert(s);
  }
  return ret;
}

bool MakeSquareNode::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

  
void MakeSquareNode::deepify(){
  uassert(!theFile&&!theRank&&theName||
	  theFile&&theRank&&!theName, "deepify msn error");
  if (theFile) theFile=theFile->clone();
  if (theRank) theRank=theRank->clone();
  if (theName) theName=theName->clone();
}
