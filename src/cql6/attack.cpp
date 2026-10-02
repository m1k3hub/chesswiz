#include "attack.h"
void Attack::initialize(){
  uassert(!CqlRunningThreads,"attack initialize crt");
  orthogonalShift(0);
  diagonalShift(0);
  betweenmask(0,0);
  kingAttacks(0);
  pawnAttacks(0,WHITE);
  knightAttacks(0);
}

SquareMask Attack::attacksquares(SquareMask squares,
				 const pieceT* board,
				 SquareMask occupied,
				 SquareMask target){
  SquareMask ret;
  if (squares.empty())return ret;
  ForMask(square,squares){
    ret |=
    attacksquare(square,board[square],occupied,target);
  }
  return ret;
}

SquareMask Attack::attacksquare(squareT square,
				pieceT piece,
				SquareMask occupied,
				SquareMask target){
  SquareMask ret;
  switch(piece){
  case EMPTY: return ret;
  case WP:
    return pawnAttacks(square,WHITE)&target;
  case BP:
    return pawnAttacks(square,BLACK)&target;
  case WK:case BK:
    return kingAttacks(square)&target;
  case WN:case BN:
    return knightAttacks(square)&target;
  case WQ:case BQ:
    return attacksquare(square, WR, occupied, target) |
      attacksquare(square,WB,occupied,target);
  case WR:case BR:{
    SquareMask ortho= orthogonalShift(square) & target;
    if(ortho.empty())return ret;
    for(squareT i=0;i<64;++i)
      if (ortho.member(i) &&
	  (betweenmask(square,i)&occupied).empty())
	ret.insert(i);
    return ret;
  }
  case WB:case BB:{
    SquareMask diag = diagonalShift(square) & target;
    if (diag.empty()) return ret;
    for (squareT i=0;i<64;++i)
      if (diag.member(i) &&
	  (betweenmask(square,i)&occupied).empty())
	ret.insert(i);
    return ret;
  }
  }
  uassert(false,"attacksquare switch");
  return ret;
}


SquareMask Attack::orthogonalShift(squareT square){
  uassert(square_valid(square),"orthogonalShift square");
  static bool computed{false};
  static SquareMask array[64];
  if (!computed){
    uassert(!CqlRunningThreads,"Aos crt");
    vector<Direction> directions=Direction::orthogonalDirections();
    uassert(directions.size()==4,"os internal");
    for (squareT source=0;source<64;++source)
      for (Direction d:directions)
	for (squareT target=0;target<64;++target)
	  if(d.reachable(source,target))
	    array[source].insert(target);
    computed=true;
  }
  return array[square];
}

SquareMask Attack::diagonalShift(squareT square){
  uassert(square_valid(square),"DiagonalShift square");
  static bool computed{false};
  static SquareMask array[64];
  if (!computed){
    uassert(!CqlRunningThreads,"DS crt");
    vector<Direction> directions=Direction::diagonalDirections();
    uassert(directions.size()==4,"ds internal");
    for (squareT source=0;source<64;++source)
      for (Direction d:directions)
	for (squareT target=0;target<64;++target)
	  if(d.reachable(source,target))
	    array[source].insert(target);
    computed=true;
  }
  return array[square];
}

SquareMask Attack::betweenmask(squareT source, squareT target){
  uassert(square_valid(source)&&square_valid(target),"betweenmask args");
  static bool computed{false};
  static SquareMask array[64][64];
  if(!computed){
    uassert(!CqlRunningThreads,"Abm crt");
    for (squareT i=0;i<64;++i)
      for (squareT j=0;j<64;++j)
	array[i][j]=Direction::between(i, j);
    computed=true;
  }
  return array[source][target];
}
  
SquareMask Attack::kingAttacks(squareT square){
  uassert(square_valid(square),"kingAttacks arg");
  static bool computed{false};
  static SquareMask array[64];
  if(!computed){
    uassert(!CqlRunningThreads,"AkA crt");
    int fileoffsets[8]={0,1,1,1,0,-1,-1,-1};
    int rankoffsets[8]={1,1,0,-1,-1,-1,0,1};
    for(squareT s=0;s<64;++s)
      for (int i=0;i<8;++i){
	squareT newsquare=shift(s,fileoffsets[i],rankoffsets[i]);
	if(square_valid(newsquare))
	  array[s].insert(newsquare);
      }
    computed=true;
  }
  return array[square];
}

SquareMask Attack::pawnAttacks(squareT square, colorT color){
  uassert(square_valid(square),"pawnattacks square");
  uassert(color==WHITE||color==BLACK,"pawnattacks color");
  static bool computed{false};
  static SquareMask array[64][2];
  if(!computed){
    uassert(!CqlRunningThreads,"Apa crt");        
    for (int tmpicolor=0;tmpicolor<2;++tmpicolor){
      for(squareT s=0;s<64;++s){
	int rankoff= (tmpicolor==(int)WHITE) ? 1 : -1;
	squareT left=shift(s,-1,rankoff);
	squareT right=shift(s,1,rankoff);
	if (square_valid(left))
	  array[s][tmpicolor].insert(left);
	if (square_valid(right))
	  array[s][tmpicolor].insert(right);
      }
      computed=true;
    }
    } // if !computed
  return array[square][(int)color];
}


SquareMask Attack::knightAttacks(squareT square){
  uassert(square_valid(square),"knightattack square");
  static bool computed{false};
  static SquareMask array[64];
  if(!computed){
    uassert(!CqlRunningThreads,"AkA crt");
    int fileoffsets[8]={1,2,2,1,-1,-2,-2,-1};
    int rankoffsets[8]={2,1,-1,-2,-2,-1,1,2};
    for (squareT s=0;s<64;++s)
      for(int i=0;i<8;++i) {
	squareT newsquare=shift(s,fileoffsets[i],rankoffsets[i]);
	if(square_valid(newsquare))
	  array[s].insert(newsquare);
      }
    computed=true;
  }
  return array[square];
}

squareT Attack::shift(squareT square, int fileoff, int rankoff){
  uassert(square_valid(square)&&fileoff<=2&&fileoff>=-2&&rankoff<=2&&rankoff>=-2,
	  "attackshift args");
  int file=square_Fyle(square)+fileoff;
  int rank=square_Rank(square)+rankoff;
  if (file<0||file>7||rank<0||rank>7) return 64;
  return square_Make(file,rank);
}

SquareMask Attack::pawnNormalMove(squareT square, SquareMask occupied, colorT color){
  SquareMask ret;
  uassert(square_valid(square)&&(color==WHITE||color==BLACK),"pnm args");
  uassert(occupied.member(square),"pnm occupied");
  int file=square_Fyle(square);
  int rank=square_Rank(square);
  int direction= color==WHITE ? 1 : -1;
  squareT move1=square_Make(file,rank+direction);
  if (!square_valid(move1)||occupied.member(move1))return ret;
  ret.insert(move1);
  if(rank== (color==WHITE? 1 : 6)){
    uassert(square_Rank(move1)== (color==WHITE ? 2 : 5), "pnm ranks");
    squareT move2=square_Make(file,rank+direction+direction);
    uassert(square_valid(move2),"pnm ranks 2");
    if (!occupied.member(move2))ret.insert(move2);
  }
  return ret;
}

bool Attack::enpassantAttack(QPos*qpos,
			     squareT square,
			     const pieceT*board,
			     squareT*epsquarep,
			     squareT*eptop,
			     bool allowPseudo){
  uassert(qpos&&
	  square_valid(square)&&
	  board&&
	  (board[square]==WP || board[square]==BP)&&
	  epsquarep&&
	  eptop,
	  "epa args");
  pieceT piece=board[square];
  pieceT otherpiece=(piece==WP ? BP : WP);
  colorT color=piece_Color(piece);
  uassert(color==WHITE||color==BLACK,"attackepcolor");
  int direction= color==WHITE ? 1 : -1;
  colorT tomove=qpos->getToMove();
  uassert(tomove==color,"attempt to check enpassant of wrong color pawn");
  //getting the previous move is copied from movebase.cpp MovePastNode::getMoves
  if(qpos->initial())return false;
  QMove* smt=qpos->getPreviousMove();
  squareT toprev=smt->to;
  squareT fromprev=smt->from;
  if (toprev==fromprev)return false;
  uassert(square_valid(toprev)&&square_valid(fromprev)&&board[fromprev]==EMPTY&&board[toprev]!=EMPTY,"epattack bad prev squares");
  if (board[toprev]!=otherpiece) return false;
  squareT passedover=shift(toprev,0,direction);
  uassert(square_valid(passedover),"epattack passedover");
  if(shift(passedover,0,direction)!=fromprev) return false;
  uassert(board[passedover]==EMPTY,"epattack passedover empty");
  if (square!=shift(toprev,1,0)&&
      square!=shift(toprev,-1,0))return false;
  pieceT board2[64];
  for(int i=0;i<64;++i)board2[i]=board[i];
  board2[toprev]=EMPTY;
  board2[square]=EMPTY;
  board2[passedover]=piece;
  if(!allowPseudo&&incheck(board2,color)) return false;
  *epsquarep=toprev;
  *eptop=passedover;
  return true;
}

bool Attack::incheck(const pieceT*board,
			colorT color){
  uassert(color==WHITE||color==BLACK,"incheck err");
  SquareMask colormasks[2];
  squareT kingsquares[2];
  masks_from_board(board,colormasks,kingsquares);
  colorT otherColor = color==WHITE ? BLACK : WHITE;
  SquareMask occupied=colormasks[BLACK]|colormasks[WHITE];
  SquareMask kingmask=SquareMask::fromSquare(kingsquares[color]);
  SquareMask attacks = attacksquares(colormasks[otherColor],board,occupied,kingmask);
  if (attacks.nonempty()) return true;
  return false;
}

void Attack::masks_from_board(const pieceT*board, SquareMask* masks, squareT*kingsquares){
  masks[0].clear();
  masks[1].clear();
  kingsquares[0]=kingsquares[1]=64;
  for (squareT i=0;i<64;++i){
    pieceT piece=board[i];
    if(piece==EMPTY) continue;
    colorT color=piece_Color(piece);
    if (piece==WK || piece==BK)
      kingsquares[color]=i;
    masks[color].insert(i);
  }
  uassert(square_valid(kingsquares[0])&&square_valid(kingsquares[1]),"masks_from_board kings not found");
}

SquareMask Attack::castle(QPos*qpos, SquareMask* masks, const squareT* kingsquares ){
  SquareMask ret;
  uassert(qpos&&kingsquares&&masks&&square_valid(kingsquares[0])&&square_valid(kingsquares[1]),"attack castle args");
  const pieceT* board=qpos->getBoard();
  colorT color=qpos->getToMove();
  uassert(board[kingsquares[BLACK]]==BK&&board[kingsquares[WHITE]]==WK,"acastle kings");
  squareT kingsquare=kingsquares[color];
  squareT kpos= color==WHITE ? E1 : E8; //macro in common.h
  if (kingsquare != kpos) return ret;
  vector<int> directions{1,-1};
  vector<squareT>rooksquares;
  if (color==WHITE)
    rooksquares=vector<squareT>{H1,A1};
  else
    rooksquares=vector<squareT>{H8,A8};
  SquareMask attackers=masks[1-color];
  SquareMask occupied = masks[BLACK]|masks[WHITE];
  for (int type=0;type<2;++type){
    squareT rooksquare=rooksquares[type];
    int direction=directions[type];
    squareT dest=shift(kingsquare,2*direction,0);
    pieceT goodrook=(color==WHITE?WR:BR);
    if (board[rooksquare]!=goodrook) continue;
    if ((occupied&betweenmask(kingsquare,rooksquare)).nonempty())continue;
    squareT passedover=shift(kingsquare,direction,0);
    SquareMask attackmask(vector<squareT>{kingsquare,passedover,dest});
    uassert(attackmask.count()==3,"castle am");
    SquareMask attacked=attacksquares(attackers,board,occupied,attackmask);
    if (attacked.nonempty())continue;
    SquareMask movedests=moveTos(qpos);
    if(movedests.member(kingsquare)||movedests.member(rooksquare))
      continue;
    ret.insert(dest);
  }
  return ret;
}

//All the destination of all the previous moves. Recursive - change
SquareMask Attack::moveTos(QPos*qpos){
  SquareMask ret;
  if(qpos->initial()) return ret;
  const QMove* smt=qpos->getPreviousMove();
  uassert(smt->valid,"moveTos invalid prevs");
  squareT toprev=smt->to;
  squareT fromprev=smt->from;
  uassert(square_valid(toprev)&&square_valid(fromprev),"moveTos prevs");
  if(toprev!=fromprev) // for null moves
    ret.insert(toprev);
  QPos*prev=qpos->getParent();
  ret |= moveTos(prev);
  return ret;
}
