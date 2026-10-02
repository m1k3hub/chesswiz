#include "pieceloc.h"
#include "node.h"

PieceLoc::PieceLoc(vector<PieceToken*>pts,
		   vector<SquareToken*>sts){
  vector<squareT> squares;
  colorFlags[WHITE]=colorFlags[BLACK]=false;
  uassert(pts.size()&&sts.size(),"plpl a");
  for (PieceToken* pt : pts){
    uassert(pt,"plpl b");
    if(pt->value=='a') colorFlags[BLACK]=true;
    else if (pt->value=='A') colorFlags[WHITE]=true;
    else{
      vector<pieceT> v=piecesFromChar(pt->value);
      for (pieceT p : v){
	uassert(piece_valid(p),"plpl v");
	myinsert(thePieces,p);
      }
    }
  }

  for(SquareToken* st : sts){
    uassert(st,"plplst");
    for (int file=st->minfile; file<=st->maxfile;++file)
      for(int rank=st->minrank;rank<=st->maxrank;++rank){
	uassert(file_valid(file)&&rank_valid(rank),"plpl fv");
	squareT square=square_make(file,rank);
	uassert(square_file(square)==file&&square_rank(square)==rank,"plpl sf");
	uassert(square_valid(square),"plpl sv2");
	squares.push_back(square); 
      }// for file..//for rank
  }//for each squaretoken
  squaremask=SquareMask(squares);
  std::stable_sort(thePieces.begin(),thePieces.end());
}
    

vector<pieceT> PieceLoc::piecesFromChar(char c){
  vector<pieceT> r{BR};
  vector<pieceT> n{BN};
  vector<pieceT> b{BB};
  vector<pieceT> q{BQ};
  vector<pieceT> k{BK};
  vector<pieceT> p{BP};
  vector<pieceT> R{WR};
  vector<pieceT> N{WN};
  vector<pieceT> B{WB};
  vector<pieceT> Q{WQ};
  vector<pieceT> K{WK};
  vector<pieceT> P{WP};
  vector<pieceT> A{WR,WN,WB,WQ,WK,WP};
  vector<pieceT> a{BR,BN,BB,BQ,BK,BP};
  vector<pieceT> empty{EMPTY};
  vector<pieceT> U;
  U.insert(U.end(),A.begin(),A.end());
  U.insert(U.end(),a.begin(),a.end());
  vector<pieceT> questionmark{U};
  questionmark.push_back(EMPTY);

  switch(c){
  case 'r': return r;
  case 'R': return R;
  case 'n': return n;
  case 'N': return N;
  case 'b': return b;
  case 'B': return B;
  case 'q': return q;
  case 'Q': return Q;
  case 'k': return k;
  case 'K': return K;
  case 'p': return p;
  case 'P': return P;
  case 'A': return A;
  case 'a': return a;
    //  case 'U': return U;
  case '_': return empty;
    //  case '?': return questionmark;
  };
  uassert(false,"invalid piece character");
  return U;
};

bool PieceLoc::isPurePiece(){
  if ((thePieces.size()==0&&!colorFlags[BLACK]&&!colorFlags[WHITE]) ||
      squaremask.size()<64
      )
    return false;
  return true;
}

/* for PieceLoc::hasEmptySquareMask()const, see computeorbit.cpp*/

SquareMask PieceLoc::getSquares(QPos*qpos){
  SquareMask piecemask=getPieceMask(qpos);
  SquareMask ret=piecemask&squaremask;
  return ret;
}

SquareMask PieceLoc::getPieceMask(QPos*qpos){
  auto* masks=qpos->getPieceMasks();
  SquareMask ret;
  for (pieceT piece : thePieces)
    ret |= masks->at(piece);
  if(colorFlags[WHITE])
    ret |= qpos->getColorMask(WHITE);
  if(colorFlags[BLACK])
    ret |= qpos->getColorMask(BLACK);
  return ret;
}

/* check this pieceloc against a piece type which should be 
   a white piece or EMPTY. If EMPTY return false. Else
   just look at the type of the piece*/

bool PieceLoc::match_piecetype(pieceT p){
  if (p==EMPTY) return false;
  if(colorFlags[WHITE]||colorFlags[BLACK]) return true;
  pieceT ptype=piece_Type(p);
  for (pieceT thispiece:thePieces)
    if(thispiece!=EMPTY &&
       piece_Type(thispiece)==ptype)
      return true;
  return false;
}
