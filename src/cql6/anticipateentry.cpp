#include "anticipateentry.h"
#include "squaremask.h"
using std::array;
AnticipateEntry::AnticipateEntry
(const string&key,
 int gamenumber,
 int movenumber,
 colorT sidetomove,
 Transform*t):
  key(key),
  gameNumber(gamenumber),
  moveNumber(movenumber),
  sideToMove(sidetomove),
  theTransform(t){
  uassert(gamenumber>0,"ad bad gn");
  uassert(movenumber>=0,"ad bad mn");
  uassert(key.size()>=4,"ad bad key");
  uassert(color_valid(sideToMove),"ad bad color");
}

/*static*/
bool AnticipateEntry::transformable(const array<pieceT,64>& b, Transform*T){
  uassert(T,"aetransformable 1 T");
  for(int sq=0;sq<64;++sq)
    if(b.at(sq)!=EMPTY&&!square_valid(T->transform(sq)))
      return false;
  return true;
}

/*static*/
array<pieceT,64> AnticipateEntry::transform(const array<pieceT,64>& b,Transform*T){
  uassert(T,"AE transform t");
  array<pieceT,64> nb;
  for(int sq=0;sq<64;++sq)
    nb[sq]=EMPTY;
  for(int oldsq=0;oldsq<64;++oldsq){
    if (b[oldsq]==EMPTY)continue;
    int newsq = T->transform(oldsq);
    uassert(square_valid(newsq),"bad T/sq in aet");
    nb[newsq]=b[oldsq];
  }
  return nb;
}

string AnticipateEntry::toString()const{
  stringstream s;
  s<<"AnticipateEntry: key: "<<key;
  s<<" gamenumber: "<<gameNumber;
  s<<" movenumber: "<<moveNumber;
  if (sideToMove==WHITE) s<<" wtm ";
  else s<<" btm ";
  if(theTransform)
    s<< " Transform: "<< theTransform->toString();
  return s.str();
}

array<pieceT,64> AnticipateEntry::convertBoard(const pieceT*board){
  array<pieceT,64>ret;
  for(int i=0;i<64;++i)ret[i]=board[i];
  return ret;
}

string AnticipateEntry::computeKey(const array<pieceT,64>&b,colorT sidetomove){
  stringstream s;
  for(int sq=0;sq<64;++sq){
    pieceT p=b[sq];
    if(b[sq]==EMPTY)continue;
    s<<PIECE_CHAR[p];
    s<<SquareMask::fromSquare(sq).listString();
    s<<' ';
  }
  if (sidetomove==WHITE) s<<"wtm";
  else s<<"btm";
  return s.str();
}

vector<AnticipateEntry> AnticipateEntry::entriesFromQPos(const QPos* qpos,
							 const vector<Transform*>transforms){
  array<pieceT,64>b;
  const pieceT*qp=qpos->board;
  for(int sq=0;sq<64;++sq)b[sq]=qp[sq];
  colorT sidetomove=qpos->getToMove();
  QGame*qgame=qpos->qgame;
  uassert(qgame,"bad qgame aefqpos");
  int gamenumber=qpos->qgame->getGameNumber();
  int movenumber=qpos->getMoveNumber();
  vector<AnticipateEntry>ret;
  for(Transform*t:transforms){
    if(!transformable(b,t))continue;
    array<pieceT,64>newb=transform(b,t);
    ret.push_back(
		  AnticipateEntry(computeKey(newb,sidetomove),
				gamenumber,
				movenumber,
				sidetomove,
				t));
  }
  return ret;
}

/*static*/
string AnticipateEntry::computeKey(const pieceT* board,colorT sidetomove){
  return computeKey(convertBoard(board),sidetomove);
}

string AnticipateEntry::computeKey(const QPos* qpos){
  return computeKey(qpos->getBoard(),
		    qpos->getToMove());
}
  
