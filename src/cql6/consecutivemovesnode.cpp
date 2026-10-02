#include "consecutivemovesnode.h"
using std::make_pair;
ConsecutiveMovesNode::ConsecutiveMovesNode(PositionVariable* l,
					   PositionVariable* r,
					   Range*ra,
					   bool quiet):left(l),right(r),range(ra),quiet(quiet){
  uassert(left&&right&&left->isPosition()&&right->isPosition(),"cmn args");
  uassert(ra,"ConsecutiveMovesNode: expected nonempty range");
  uassert(left!=right,"Position arguments to ConsecutiveMovesNode must be different"); //so comments work  
  }


bool ConsecutiveMovesNode::isNumeric()const{return true;}

int longestCommonSubstring(std::vector<int>a,
			   std::vector<int>b,
			   int* astart,
			   int*bstart);

void ConsecutiveMovesNode::deepify(){
  left=left->clone();
  right=right->clone();
}

bool ConsecutiveMovesNode::match_count(QPos*qpos, NumValue*valuep){
  QPos*leftpos{NULL};
  QPos*rightpos{NULL};
  uassert(valuep,"cmnmc arg");
  if(!left->match_positionvalue(qpos,&leftpos))
    return false;
  if(!right->match_positionvalue(qpos,&rightpos))
    return false;
  vector<pair<QMove*,QMove*>> pairs= compute(leftpos,rightpos);
  int len= (int)(pairs.size());
  if(len==0)return false;
  uassert(range->valid(len),"Unexpected len value in ConsecutiveMovesNodes::match_count");
  if(pairs.size()>bestMovePath.size())
    bestMovePath=pairs;
  *valuep=len;
  return true;
}
bool ConsecutiveMovesNode::match_position(QPos*qpos){
  NumValue len=-1000;
  return match_count(qpos,&len);
}

void ConsecutiveMovesNode::clear(){
  bestMovePath.clear();
}

void ConsecutiveMovesNode::annotate(){
  if(CqlCommentLevel<=CommentLevel::Quiet)return;
  if(quiet)return;
  if(!bestMovePath.size())return;
  makeComments(bestMovePath);
}

vnode ConsecutiveMovesNode::children()const{
  vnode ret{left};
  if(left!=right) ret.push_back(right);
  return ret;
}

vector<QMove*> ConsecutiveMovesNode::movepath(QPos*start, QPos*finishorig){
  vector<QMove*>ret;
  QPos*finish=finishorig;
  if(finish==start)return ret;
  while(finish!=start){
    QMove*prevmove=finish->getPreviousMove();
    uassert(prevmove&&prevmove->valid,"cmnmp badmove");
    uassert(prevmove->tail==finish,"cnmp internal finish");
    ret.push_back(prevmove);
    finish=prevmove->head;
  }
  std::reverse(ret.begin(),ret.end());
  uassert(ret.size(),"unexpected null ret cmn movepath");
  uassert(ret.size()==finishorig->getPly()-start->getPly(),"cmn movepath ply");
  uassert(ret.size()&& ret.front()->head==start&&ret.back()->tail==finishorig,"cmn movepath bad path");
  return ret;
}
    
vector<pair<QMove*,QMove*>> ConsecutiveMovesNode::compute(QPos*leftpos, QPos*rightpos){
  uassert(leftpos&&rightpos,"cmn compute args");
  vector<pair<QMove*,QMove*>> ret;
  if(leftpos==rightpos)return ret;
  QPos*L=QPos::lca(leftpos,rightpos);
  if(L==leftpos||L==rightpos)return ret;
  vector<QMove*>leftpath=movepath(L,leftpos);
  vector<QMove*>rightpath=movepath(L,rightpos);
  uassert(leftpath.front()->head==L&&leftpath.back()->tail==leftpos&&leftpath.size()==leftpos->getPly()-L->getPly(),"cmn compute bad leftpath");
  uassert(rightpath.front()->head==L&&rightpath.back()->tail==rightpos&&rightpath.size()==rightpos->getPly()-L->getPly(),"cmn compute bad rightpath");
  vector<int>leftints=movepath_to_ints(leftpath);
  vector<int>rightints=movepath_to_ints(rightpath);
  uassert(leftints.size()==leftpath.size()&&rightints.size()==rightpath.size(),"cmn sizes");
  int leftstarti=-1, rightstarti=-2;
  int mylen=longestCommonSubstring(leftints,rightints,&leftstarti,&rightstarti);
  if(!mylen)return ret;
  if(!range->valid(mylen))return ret;
  uassert(mylen<=leftints.size()&&mylen<=rightints.size()&&
	  leftstarti>=0&&rightstarti>=0&&
	  leftstarti<leftints.size()&&
	  rightstarti<rightints.size(),"cmn bad lcs return");
  uassert(mylen + leftstarti<=leftints.size(),"cmn leftintssize a");
  uassert(mylen + rightstarti<=rightints.size(),"cmn rightintssize a");
  for (int i=0;i<mylen;++i){
    QMove*leftmove=leftpath.at(leftstarti+i);
    QMove*rightmove=rightpath.at(rightstarti+i);
    ret.push_back(make_pair(leftmove,rightmove));
  }
  return ret;
}
  
void ConsecutiveMovesNode::makeComments(vector<pair<QMove*,QMove*>> &pairs){
  string leftname=left->name;
  string rightname=right->name;
  int len=(int)pairs.size();
  for (int i=0;i<len;++i){
    QMove*leftmove=pairs[i].first;
    QMove*rightmove=pairs[i].second;
    uassert(leftmove->valid&&rightmove->valid&&
	    leftmove->from==rightmove->from &&
	    leftmove->to==rightmove->to &&
	    leftmove->getMovingPiece()==rightmove->getMovingPiece(),
	    "cmn makecomments bad pairs");
    QPos*leftpos=leftmove->tail;
    QPos*rightpos=rightmove->tail;
    uassert(leftpos!=rightpos,"cmn makecomment tails");
    uassert(leftpos&&rightpos,"cmn makecomment tails2");
    stringstream lefts;
    lefts<<leftname<<"-move["<<i+1<<"]";
    stringstream rights;
    rights<<rightname<<"-move["<<i+1<<"]";
    leftpos->appendComment(lefts.str());
    rightpos->appendComment(rights.str());
  }
}

vector<int>ConsecutiveMovesNode::movepath_to_ints(vector<QMove*>&movepath){
  vector<int>ret;
  for(QMove* qmove : movepath)
    ret.push_back(qmove_to_int(qmove));
  return ret;
}

int ConsecutiveMovesNode::qmove_to_int(QMove*qmove){
  uassert(qmove&&qmove->valid,"bad qmove cmnqmti");
  squareT from=qmove->from;
  squareT to=qmove->to;
  int piece=(int)(qmove->getMovingPiece());
  uassert(square_valid(from)&&square_valid(to)&&piece>0,"qmti bad fromt");
  int ret= (to*100+from)*100 + piece;
  uassert(ret>0&&ret<5000000,"cmn::qmti ret");
  return ret;
}


