#include "qmove.h"
#include "markboard.h"
/*game is the game of the following position. Board is the board
of the previous position
*/

QMove::QMove(Game*game,const pieceT*board){
  valid=true;
  colorT color=color_other(MarkBoard::getToMove(game));
  uassert(game&&board,"qmove args");
  simpleMoveT* move=MarkBoard::getPreviousMove(game);
  from=move->from;
  to=move->to;
  uassert(square_valid(from)&&square_valid(to),"qmove internal square");
  pieceT frompiece=board[from];
  uassert(piece_Color(frompiece)==color,"qmove bad color");
  uassert(frompiece!=EMPTY,"Qmove: move from empty square");
  if(from==to){ //null move
    uassert(piece_Type(frompiece)==KING,"qmove bad null move");
    return;}
  promote=move->promote;
  if(promote!=EMPTY)
    uassert(piece_Type(frompiece)==PAWN,"qmove bad promote");
  squareT origcaptured=move->capturedSquare;
  if(to!=origcaptured&&square_valid(origcaptured)){
    enpassant=origcaptured;
    uassert(piece_Type(frompiece)==PAWN,"qmove bad ep");
    uassert(board[to]==EMPTY&&promote==EMPTY,"qmove bad ep 2");
  }
}

    
#include "qpos.h"
pieceT QMove::getMovingPiece()const{
  uassert(valid,"not a valid qmove in gmp");
  const pieceT*board=head->getBoard();
  uassert(square_valid(from),"bad from square in qmove::getmovingpiece");
  pieceT piece=board[from];
  uassert(piece!=EMPTY && piece_valid(piece),"unexpected bad piece getmovingpiece from");
  return piece;
}

/* the below uses simple castle rules and assumes that
*/
markT QMove::movingPieceId()const{
  uassert(!isCastle(),"qmove movingpieceid or castle");
  squareT fromsq=from;
  uassert(square_valid(from),"qm gmpi bad from");
  markT mark=head->squares_to_marks[fromsq];
  uassert(mark.isValid()&&head->marks_to_squares[mark.getValue()]==fromsq,"bad mark in getMovingPieceId()");
  return mark;
}

markT QMove::castleKingId()const{
  uassert(isCastle(),"qmove: gcki but no castle");
  squareT ksquare=castleKingFrom();
  uassert(square_valid(ksquare),"gcki bad king");
  markT ret= head->squares_to_marks[ksquare];
  if(head->toMove==WHITE)
    uassert(head->getPiece(ksquare)==WK,"ckid wk");
  else if (head->toMove==BLACK)
    uassert(head->getPiece(ksquare)==BK,"ckid bk");
  uassert(ret.isValid(),"bad mark in getCastleKingId()");
  return ret;
}

markT QMove::castleRookId()const{
  uassert(isCastle(),"qmove: gcki but no castle");
  squareT rsquare=castleRookFrom();
  uassert(square_valid(rsquare),"gcki bad rook");
  markT ret= head->squares_to_marks[rsquare];
  uassert(ret.isValid(),"bad mark in getCastleRookId()");
  return ret;
}


bool QMove::isNonCapture()const{
  return head->getBoard()[to]==EMPTY &&
    !isEnPassant();
}

squareT QMove::getCaptureSquare()const{
  const squareT none=65;
  uassert(valid,"QMove::capture square: not valid");
  if (isNull()) return none;
  if(isEnPassant()){
    squareT ret=getEnPassantSquare();
    uassert(square_valid(ret),"QMove enpassant/capture internal");
    return ret;
  }
  uassert(head&&square_valid(to),"QMove capture square internal to");
  const pieceT*board=head->getBoard();
  if(board[to]==EMPTY)return none;
  return to;
}

markT QMove::capturedPieceId()const{
  uassert(isCapture(),"qcpi capture");
  squareT s=getCaptureSquare();
  uassert(square_valid(s),"qcpi capture");
  markT mark=head->squares_to_marks[s];
  uassert(mark.isValid()&&head->marks_to_squares[mark.getValue()]==s,"qmcpi mark");
  return mark;
}

bool QMove::isOO()const{
  return
    (getMovingPiece()==WK
    &&from==E1
   && to==G1)
    ||
    (getMovingPiece()==BK
     &&from==E8
     &&to==G8);
}

bool QMove::isOOO()const{
  return
    (getMovingPiece()==WK
    &&from==E1
   && to==C1)
    ||
    (getMovingPiece()==BK
     &&from==E8
     &&to==C8);
}

bool QMove::isCastle()const{
  return isOO()||isOOO();
}

squareT QMove::castleKingFrom()const{
  if (isCastle())
    return from;
  else return NULL_SQUARE;
}

squareT QMove::castleKingTo()const{
  if(isCastle())
    return to;
  else return NULL_SQUARE;
}

squareT QMove::castleRookFrom()const{
  if(!isCastle())return NULL_SQUARE;
  if(isOO()&&from==E1) return H1;
  else if (isOO()&&from==E8)return H8;
  else if (isOOO()&&from==E1)return A1;
  else if (isOOO()&&from==E8)return A8;
  uassert(false,"castlerfrom bad from");
  return NULL_SQUARE;
}

squareT QMove::castleRookTo()const{
  if(isNonCastle())return NULL_SQUARE;
  if(isOO()&&from==E1) return F1;
  else if (isOO()&&from==E8)return F8;
  else if (isOOO()&&from==E1)return D1;
  else if (isOOO()&&from==E8)return D8;
  uassert(false,"castlerfrom bad from");
  return NULL_SQUARE;
}

SquareMask QMove::fatFrom()const{
  SquareMask base=SquareMask::fromSquare(from);
  if(isNonCastle()) return base;
  return base|SquareMask::fromSquare(castleRookFrom());
}

SquareMask QMove::fatTo()const{
  SquareMask base=SquareMask::fromSquare(to);
  if(isNonCastle()) return base;
  return base|SquareMask::fromSquare(castleRookTo());
}


SquareMask QMove::castleFrom()const{
  if(isNonCastle())return SquareMask();
  return SquareMask::fromSquare(from)
    | SquareMask::fromSquare(castleRookFrom());
}

SquareMask QMove::castleTo()const{
  if(isNonCastle())return SquareMask();
  return SquareMask::fromSquare(to)
    | SquareMask::fromSquare(castleRookTo());
}

/*given to masks indicating allowable squares for the true from and to
  of the current move, return the set of from squares including castling
  compatible with these masks
*/

bool QMove::validMove(SquareMask leftmask, SquareMask rightmask,CaptureType cap)const{
  if(captureTypeIsNonCapture(cap))
     return smartFrom(leftmask,rightmask).nonempty();
  uassert(captureTypeIsCapture(cap),"expected a capture in validMove()");
  if(isNonCapture())return false;
  squareT capsq=getCaptureSquare();
  uassert(square_valid(capsq),"qmvm cap");
  return leftmask.member(from)&&
    rightmask.member(capsq);
}

bool QMove::invalidMove(SquareMask frommask, SquareMask tomask,CaptureType cap)const{
  return !validMove(frommask,tomask,cap);
}

SquareMask QMove::smartFrom(SquareMask frommask, SquareMask tomask)const{
  /*keep in sync with QMove::smartTo*/
  if (isNonCastle())
    if(tomask.member(to))
      return frommask & getSimpleFromMask();
    else
      return SquareMask{};

  SquareMask ret;
  if(tomask.member(castleKingTo()))
    ret=frommask&castleKingFromMask();
  if(tomask.member(castleRookTo()))
    ret|=frommask&castleRookFromMask();
  return ret;
}

SquareMask QMove::smartTo(SquareMask frommask, SquareMask tomask)const{
  /*Keep in sync with QMove::smartFrom*/
  if (isNonCastle())
    if(frommask.member(from))
      return tomask & getSimpleToMask();
    else
      return SquareMask{};

  SquareMask ret;
  if(frommask.member(castleKingFrom()))
    ret=tomask&castleKingToMask();
  if(frommask.member(castleRookFrom()))
    ret|=tomask&castleRookToMask();
  return ret;
}




    
    
    
