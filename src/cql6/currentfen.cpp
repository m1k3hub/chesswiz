#include "currentfen.h"
bool CurrentFen::match_position(QPos*qpos){
  eassert(false,"attempt to determine if 'currentfen' matches the current position, which it always does. Perhaps you intended to use its string value");
  return false;
}

bool CurrentFen::match_stringvalue(QPos*qpos,string*valp){
  uassert(valp&&qpos,"cfmsv currentfen bad arg");
  *valp= toFen(qpos);
  return true;
}

string CurrentFen::toFen(QPos*qpos){
  const pieceT*board=qpos->getBoard();
  int emptycount=0;
  stringstream s;
  for (int rank=7;rank>=0;--rank){
    for (int file=0;file<=7;++file){
      squareT square=square_make(file,rank);
      pieceT currentpiece=board[square];
      bool isempty=(currentpiece==EMPTY);
      if (isempty) ++ emptycount;
      else {
	if (emptycount>0){
	  s<<emptycount;
	  emptycount=0;
	}
	s<<piece_to_char(currentpiece);
      }//nonempty piece
    }//for file = 0 to 7
    if (emptycount>0){
      s<<emptycount;
      emptycount=0;}
    if (rank>0)
      s<<"/";
  }//for rank=7 to 0
  s<<' '
   <<getColorString(qpos)
   <<' '
   <<getCastleString(qpos)
   <<' '
   <<epString(qpos);

  s<<" 0 1";
  return s.str();
}

string CurrentFen::getColorString(QPos*qpos){
  uassert(qpos,"cfgcs color");
  switch (qpos->getToMove()){
  case WHITE: return "w";
  case BLACK: return "b";
  default: uassert(false,"bad color");
  }
  uassert(false,"bad color  2");
  return "";
}

      
string CurrentFen::getCastleString(QPos*qpos){
  SquareMask forbiddenmask=forbiddenCastleMask(qpos);
  SquareMask okmask= ~forbiddenmask;
  stringstream s;
  if (okmask.member(H1))
    s<<'K';
  if (okmask.member(A1))
    s<<'Q';
  if (okmask.member(H8))
    s<<'k';
  if (okmask.member(A8))
    s<<'q';
  string ret=s.str();
  if (ret.empty()) ret="-";
  return ret;
}

SquareMask CurrentFen::currentForbiddenCastleMask(QPos*qpos){
  SquareMask ret;
  uassert(qpos,"cfccm");
  const pieceT*board=qpos->getBoard();
  if (board[A1]!=WR||board[E1]!=WK) ret.insert(A1);
  if (board[H1]!=WR||board[E1]!=WK) ret.insert(H1); 
  if (board[A8]!=BR||board[E8]!=BK) ret.insert(A8);
  if (board[H8]!=BR||board[E8]!=BK) ret.insert(H8); 
  return ret;
}

SquareMask CurrentFen::forbiddenCastleMask(QPos*qpos){
  uassert(qpos,"cfcfccm compute");
  SquareMask ret;
  QPos*cursor=qpos;
  while (cursor){
    ret|=currentForbiddenCastleMask(cursor);
    cursor=cursor->getParent();
  }
  return ret;
}

string CurrentFen::epString(QPos*qpos){
  if (!qpos->getParent())return "-";
  QMove* previous=qpos->getPreviousMove();
  uassert(previous,"cf epst");
  pieceT piecetype=previous->getMovingPiece();
  squareT from = previous->from;
  squareT to = previous->to;
  if (!(piecetype==WP || piecetype==BP))
    return "-";
  uassert(square_valid(from)&&square_valid(to),"CurrentFen:epString: internal");
  int rankfrom=square_Rank(from);
  int filefrom=square_Fyle(from);
  int rankto=square_Rank(to);
  int fileto=square_Fyle(to);
  if (abs(rankfrom-rankto)!=2) return "-";
  uassert(filefrom==fileto,"CurrentFen::epString: bad files: internal");
  int newrank = (rankto + rankfrom) /2;
  int newfile= fileto;
  uassert(rank_valid(newrank)&&file_valid(newfile),"currentfen ep filerank internal");
  return util::squarestring(newfile,newrank);
}
  
    
